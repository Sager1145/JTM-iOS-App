#!/usr/bin/env python3
"""Drive the DEBUG RailMap app (com.JRM.RailMap) without touching the screen (stdlib only; run with -I).

  app-control.py --target sim|mac|device [--device UDID] COMMAND [key=value ...] [--json '{...}']
  app-control.py --target T build|install|launch|terminate|ready|pull-screenshot ...

Commands go to the app's test control channel (DEBUG builds only): a railmap-test://run URL
(inline request, or ?request=<id> naming inbox/<id>.json in the app container). The app runs the
command through its own stores and views and writes results/result-<id>.json, which this tool waits
for by request ID and prints as one compact JSON line.

Commands: loadSamples useStorage reloadAll state selectTrip focusTrip openEditor addTrip editTrip
saveEditor cancelEditor deleteTrip openStats setHideFilter screenshot wait devtools exportDiagnostics
clearRouteCaches memoryWarning setLayer camera perf tapMap (tapCount=2 for a double tap).
Values parse as JSON when they can (numbers, true/false, [..], {..}); otherwise they are strings.

Exit: 0 ok, 2 rejected (bad request, or refused because the app is on the shared store),
3 timeout, 4 failed, 1 tool/usage error. One native app job at a time across all chats.
"""
import argparse, base64, re, hashlib, json, os, plistlib, shutil, subprocess, sys, tempfile, time, uuid
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
BUNDLE = "com.JRM.RailMap"
SCHEME = "railmap-test"
ROOT_NAME = "RailMapAppControl"
CONTAINER_ROOT = "Library/Application Support/" + ROOT_NAME
DEFAULT_SIM = "0DBE2488-0BEB-4932-9B55-091B3CC793B6"
DEFAULT_DEVICE = "00008140-000575142288801C"
# One build folder per worktree: sharing one let another session's build replace the app
# a run was about to measure (the app then ran a different commit than the one under test).
WORKTREE_KEY = hashlib.sha1(str(REPO).encode("utf-8")).hexdigest()[:10]
DERIVED = Path(os.path.expanduser("~/Library/Caches/jtm-railmap-app-control/DerivedData")) / WORKTREE_KEY
PLATFORM_SUFFIX = {"sim": "iphonesimulator", "mac": "maccatalyst", "device": "iphoneos"}
DESTINATIONS = {"sim": "platform=iOS Simulator,id={device}", "mac": "platform=macOS,variant=Mac Catalyst",
                "device": "generic/platform=iOS"}  # no unlocked device needed to build
STATE_DIR = Path(os.path.expanduser("~/Library/Caches/jtm-railmap-app-control"))
COMMANDS = ["loadSamples", "useStorage", "reloadAll", "state", "selectTrip", "focusTrip", "openEditor",
            "addTrip", "editTrip", "saveEditor", "cancelEditor", "deleteTrip", "openStats", "setHideFilter",
            "screenshot", "wait", "devtools", "exportDiagnostics", "clearRouteCaches", "memoryWarning", "setLayer",
            "camera", "perf", "tapMap"]
DEVTOOLS_ACTIONS = ["show", "hide", "expand", "collapse", "recorderOn", "recorderOff", "resetSignposts", "export"]
# CLI wait (seconds) per command when no timeoutMs is passed: at least the app-side default.
DEFAULT_WAIT = {"reloadAll": 660, "addTrip": 200, "editTrip": 200, "openEditor": 90, "saveEditor": 60,
                "loadSamples": 240, "exportDiagnostics": 120, "wait": 90}
EXIT = {"ok": 0, "rejected": 2, "timeout": 3, "failed": 4}
DEV_ENV = {"DEVELOPER_DIR": os.environ.get("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")}


def out(obj, code):
    print(json.dumps(obj, ensure_ascii=False, separators=(",", ":")))
    sys.exit(code)


def run(cmd, check=True, capture=True, timeout=600, env=None):
    full_env = dict(os.environ, **DEV_ENV, **(env or {}))
    p = subprocess.run(cmd, capture_output=capture, text=True, timeout=timeout, env=full_env)
    if check and p.returncode != 0:
        text = (p.stderr or "") + (p.stdout or "")
        hint = ("unlock the iPhone (iOS refuses launches while locked)" if "Locked" in text or "unlocked" in text
                else "trust the developer certificate on the device (Settings > General > VPN & Device Management)"
                if "invalid code signature" in text or "Untrusted" in text else None)
        out({"error": "command failed", "hint": hint, "cmd": cmd, "code": p.returncode,
             "stderr": (p.stderr or "")[-2000:], "stdout": (p.stdout or "")[-1000:]}, 1)
    return p


def device_id(a):
    return a.device or (DEFAULT_SIM if a.target == "sim" else DEFAULT_DEVICE if a.target == "device" else "mac")


def head_commit():
    """Full HEAD sha of this worktree, or None outside git."""
    p = subprocess.run(["git", "-C", str(REPO), "rev-parse", "HEAD"], capture_output=True, text=True)
    return p.stdout.strip() if p.returncode == 0 and p.stdout.strip() else None


def build_commit_stamp():
    """HEAD sha stamped into Info.plist at build time; `-dirty` when tracked files or untracked files under ios/ differ from HEAD."""
    head = head_commit()
    if not head:
        return "unknown"
    status = subprocess.run(["git", "-C", str(REPO), "status", "--porcelain", "--untracked-files=normal", "--", "ios"],
                            capture_output=True, text=True)
    dirty = status.returncode != 0 or bool(status.stdout.strip())
    return head + ("-dirty" if dirty else "")


def built_commit(app):
    """The commit stamped into a built app's Info.plist, or None when the app has none."""
    for rel in ("Contents/Info.plist", "Info.plist"):
        try:
            value = plistlib.loads((Path(app) / rel).read_bytes()).get("JTMBuildCommit")
        except (OSError, ValueError):
            continue
        return value or None
    return None


def commit_mismatch(stamped, head):
    """True when the stamped build is not HEAD (ignores the `-dirty` suffix)."""
    return not stamped or not head or stamped.split("-dirty")[0] != head


def app_path(a):
    if a.app:
        return Path(a.app)
    return DERIVED / "Build/Products" / "{}-{}".format(a.configuration, PLATFORM_SUFFIX[a.target]) / "RailMap.app"


def state_file(a):
    # Keyed on the worktree too: another worktree's `state` or `quit` must not reach this one's app.
    return STATE_DIR / "{}-{}-{}.json".format(a.target, device_id(a), WORKTREE_KEY)


def remember(a, **values):
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    data = recall(a)
    data.update(values)
    state_file(a).write_text(json.dumps(data, indent=1), encoding="utf-8")


def recall(a):
    try:
        return json.loads(state_file(a).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


# ---------------------------------------------------------------- container access

def local_root(a):
    """Host path of the control root for sim and mac (device has none)."""
    if a.target == "sim":
        p = run(["xcrun", "simctl", "get_app_container", device_id(a), BUNDLE, "data"], check=False)
        if p.returncode != 0:
            out({"error": "app not installed on simulator", "device": device_id(a), "stderr": p.stderr.strip()}, 1)
        return Path(p.stdout.strip()) / CONTAINER_ROOT
    if a.target == "mac":
        sandboxed = Path(os.path.expanduser("~/Library/Containers/{}/Data/{}".format(BUNDLE, CONTAINER_ROOT)))
        plain = Path(os.path.expanduser("~/Library/Application Support/" + ROOT_NAME))
        candidates = [r for r in (plain, sandboxed) if (r / "ready.json").exists()]
        if candidates:
            return max(candidates, key=lambda r: (r / "ready.json").stat().st_mtime)
        return plain
    return None


def devicectl_copy(a, direction, source, destination):
    cmd = ["xcrun", "devicectl", "device", "copy", direction, "--device", device_id(a),
           "--source", str(source), "--destination", str(destination),
           "--domain-type", "appDataContainer", "--domain-identifier", BUNDLE, "-q", "--timeout", "30"]
    return run(cmd, check=False, timeout=60)


def read_container_file(a, relative):
    """Bytes of a file under the control root, or None."""
    root = local_root(a)
    if root is not None:
        try:
            return (root / relative).read_bytes()
        except OSError:
            return None
    with tempfile.TemporaryDirectory() as tmp:
        dest = Path(tmp) / "f"
        p = devicectl_copy(a, "from", CONTAINER_ROOT + "/" + relative, dest)
        if p.returncode != 0 or not dest.exists():
            return None
        return dest.read_bytes()


def write_container_file(a, relative, data):
    root = local_root(a)
    if root is not None:
        target = root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        tmp = target.with_suffix(".tmp")
        tmp.write_bytes(data)
        tmp.rename(target)
        return
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / Path(relative).name
        src.write_bytes(data)
        p = devicectl_copy(a, "to", src, CONTAINER_ROOT + "/" + relative)
        if p.returncode != 0:
            out({"error": "devicectl copy to failed", "stderr": p.stderr[-2000:]}, 1)


def open_url(a, url):
    if a.target == "sim":
        run(["xcrun", "simctl", "openurl", device_id(a), url])
    elif a.target == "mac":
        app = app_path(a)
        cmd = ["open", "-g"] + (["-a", str(app)] if app.exists() else ["-b", BUNDLE]) + [url]
        run(cmd)
    else:
        run(["xcrun", "devicectl", "device", "process", "openURL", "--device", device_id(a), url, "-q",
             "--timeout", "30"], timeout=60)


# ---------------------------------------------------------------- send

def parse_value(text):
    try:
        return json.loads(text)
    except ValueError:
        return text


def build_request(command, pairs, extra_json):
    args = {}
    if extra_json:
        args.update(json.loads(extra_json))
    for pair in pairs:
        if "=" not in pair:
            out({"error": "expected key=value", "got": pair}, 1)
        key, value = pair.split("=", 1)
        args[key] = parse_value(value)
    rid = "ac-{}-{}".format(time.strftime("%H%M%S"), uuid.uuid4().hex[:8])
    return {"id": rid, "command": command, "args": args}


def send(a, request):
    rid = request["id"]
    payload = json.dumps(request, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    encoded = base64.urlsafe_b64encode(payload).decode("ascii").rstrip("=")
    started = time.time()
    if a.transport == "url" and len(encoded) < 3500:
        open_url(a, "{}://run?json={}".format(SCHEME, encoded))
    else:
        # A device copy is not atomic: `.req` tells the app to retry a file that does not decode yet.
        suffix = "req" if a.target == "device" else "json"
        write_container_file(a, "inbox/{}.{}".format(rid, suffix), payload)
        if a.transport != "poll":
            open_url(a, "{}://run?request={}".format(SCHEME, rid))
    timeout = a.timeout if a.timeout is not None else DEFAULT_WAIT.get(request["command"], 90)
    args_timeout = request["args"].get("timeoutMs")
    if isinstance(args_timeout, (int, float)):
        timeout = max(timeout, args_timeout / 1000 + 10)
    if request["command"] == "camera":
        # A ramp lasts steps x stepMs in the app, plus its settle (up to 8 s).
        steps, step_ms = request["args"].get("steps", 30), request["args"].get("stepMs", 33)
        if isinstance(steps, (int, float)) and isinstance(step_ms, (int, float)):
            timeout = max(timeout, steps * step_ms / 1000 + 30)
    interval = 1.0 if a.target == "device" else 0.15
    picked_up = False
    while time.time() - started < timeout:
        raw = read_container_file(a, "results/result-{}.json".format(rid))
        if raw:
            try:
                result = json.loads(raw.decode("utf-8"))
            except ValueError:
                result = None
            if result and result.get("id") == rid:
                picked_up = True
                if result.get("status") != "running":
                    result["roundTripMs"] = round((time.time() - started) * 1000)
                    return result
        time.sleep(interval)
    return {"id": rid, "command": request["command"], "status": "timeout", "pickedUp": picked_up,
            "error": "no final result within {}s (is the DEBUG app running? try `launch`)".format(int(timeout))}


# ---------------------------------------------------------------- helpers per target

def cmd_build(a):
    dest = DESTINATIONS[a.target].format(device=device_id(a))
    cmd = ["xcodebuild", "-project", str(REPO / "ios/RailMap.xcodeproj"), "-scheme", "RailMap",
           "-configuration", a.configuration, "-destination", dest, "-derivedDataPath", str(DERIVED),
           "-jobs", str(a.jobs), "build", "JTM_BUILD_COMMIT=" + build_commit_stamp()]
    if a.target != "device":
        cmd.append("CODE_SIGN_IDENTITY=-")  # ad-hoc: no team identity needed for sim or Catalyst
    else:
        cmd.append("-allowProvisioningUpdates")
    if a.dry_run:
        out({"cmd": cmd}, 0)
    p = run(cmd, check=False, timeout=3600)
    lines = ((p.stdout or "") + "\n" + (p.stderr or "")).splitlines()
    tail = [l for l in lines if "error:" in l or "error " in l.lower() and "xcodebuild" in l or "** BUILD" in l][-20:]
    out({"built": p.returncode == 0, "app": str(app_path(a)), "log": tail}, 0 if p.returncode == 0 else 4)


def cmd_check_release(a):
    """Release build must carry no developer-tool code, strings or URL scheme."""
    if a.configuration != "Release":
        a.configuration = "Release"
    app = app_path(a)
    script = REPO / "ios/tools/app-control/check-release-clean.sh"
    p = run(["bash", str(script), str(app)], check=False)
    out({"clean": p.returncode == 0, "app": str(app), "report": (p.stdout + p.stderr).strip().splitlines()[-30:]},
        0 if p.returncode == 0 else 4)


def cmd_install(a):
    app = app_path(a)
    if not app.exists():
        out({"error": "app not built", "app": str(app)}, 1)
    if a.target == "sim":
        run(["xcrun", "simctl", "install", device_id(a), str(app)])
    elif a.target == "device":
        run(["xcrun", "devicectl", "device", "install", "app", "--device", device_id(a), str(app), "-q"], timeout=900)
    else:
        # A Catalyst app runs in place; registering it makes `open -b` and the URL scheme resolve to this copy.
        lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        run([lsregister, "-f", str(app)], check=False)
    out({"installed": True, "target": a.target, "device": device_id(a), "app": str(app)}, 0)


def launch_env(a, storage):
    env = {"RAILMAP_UI_TEST_STORAGE_ID": storage, "RAILMAP_APP_CONTROL": "1",
           "RAILMAP_SIGNPOST_RECORDER": "1", "RAILMAP_DEVTOOLS": "0" if a.no_devtools else "1"}
    for pair in a.env or []:
        key, _, value = pair.partition("=")
        env[key] = value
    return env


def terminate(a):
    if a.target == "sim":
        run(["xcrun", "simctl", "terminate", device_id(a), BUNDLE], check=False)
    elif a.target == "mac":
        # Only this build's process: never `pkill -x RailMap`, which would also hit simulator apps
        # and other copies. The pid comes from the app's own ready.json.
        app = app_path(a)
        run(["pkill", "-f", str(app / "Contents/MacOS/RailMap")], check=False)
        raw = read_container_file(a, "ready.json")
        pid = (json.loads(raw).get("processID") if raw else None) or recall(a).get("processID")
        if pid:
            ps = run(["ps", "-o", "comm=", "-p", str(int(pid))], check=False)
            if "maccatalyst" in ps.stdout or str(app) in ps.stdout:
                run(["kill", str(int(pid))], check=False)
        time.sleep(0.8)
    else:
        pid = recall(a).get("processID")
        if pid:
            run(["xcrun", "devicectl", "device", "process", "terminate", "--device", device_id(a),
                 "--pid", str(pid), "-q"], check=False, timeout=60)


def cmd_launch(a):
    storage = a.storage
    if not storage or storage == "new":
        storage = str(uuid.uuid4())
    storage = storage.upper()
    try:
        uuid.UUID(storage)
    except ValueError:
        out({"error": "--storage must be a UUID (or 'new'); the shared store is never used"}, 1)
    env = launch_env(a, storage)
    before = read_container_file(a, "ready.json") if a.target != "device" else None
    if a.target == "sim":
        child = {"SIMCTL_CHILD_" + k: v for k, v in env.items()}
        p = run(["xcrun", "simctl", "launch", "--terminate-running-process", device_id(a), BUNDLE], env=child)
        pid = p.stdout.strip().split(":")[-1].strip()
    elif a.target == "mac":
        terminate(a)
        app = app_path(a)
        if not app.exists():
            out({"error": "app not built", "app": str(app)}, 1)
        stamped = built_commit(app)
        if not a.app and commit_mismatch(stamped, head_commit()):
            out({"error": "built app is not this worktree's HEAD; run build first",
                 "builtCommit": stamped, "head": head_commit(), "app": str(app)}, 1)
        if not a.app and stamped and stamped.endswith("-dirty") and not a.allow_dirty:
            out({"error": "built app was made from uncommitted changes that may differ from the tree now; "
                          "rebuild, or pass --allow-dirty", "builtCommit": stamped, "app": str(app)}, 1)
        cmd = ["open", "-n", "-g", "-a", str(app)]
        for k, v in env.items():
            cmd += ["--env", "{}={}".format(k, v)]
        run(cmd)
        pid = None
    else:
        with tempfile.TemporaryDirectory() as tmp:
            jpath = Path(tmp) / "launch.json"
            run(["xcrun", "devicectl", "device", "process", "launch", "--device", device_id(a),
                 "--terminate-existing", "--environment-variables", json.dumps(env), "-q",
                 "--json-output", str(jpath), BUNDLE], timeout=120)
            try:
                info = json.loads(jpath.read_text())
                pid = info.get("result", {}).get("process", {}).get("processIdentifier")
            except (OSError, ValueError):
                pid = None
    remember(a, storageID=storage, processID=pid, launchedAt=time.strftime("%Y-%m-%dT%H:%M:%S"))
    # Wait for the poller's ready marker from this launch (sim/mac; device is checked by `ready`).
    ready = None
    if a.target != "device":
        deadline = time.time() + (a.timeout or 60)
        while time.time() < deadline:
            raw = read_container_file(a, "ready.json")
            if raw and raw != before:
                ready = json.loads(raw)
                if (ready.get("storageID") or "").upper() == storage:
                    break
            time.sleep(0.25)
    if ready and ready.get("processID"):
        remember(a, processID=ready["processID"])
    out({"launched": True, "target": a.target, "device": device_id(a), "storageID": storage,
         "processID": pid, "ready": ready}, 0)


def cmd_ready(a):
    raw = read_container_file(a, "ready.json")
    out({"ready": json.loads(raw) if raw else None, "remembered": recall(a)}, 0 if raw else 4)


def pull(a, rel, default_name):
    dest = Path(a.out or Path(tempfile.gettempdir()) / default_name)
    data = read_container_file(a, rel)
    if data is None:
        out({"error": "file not found in container", "path": rel}, 4)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(data)
    return {"file": str(dest), "bytes": len(data)}


def cmd_pull(a):
    out(pull(a, "screenshots/{}.png".format(a.name), "railmap-{}-{}.png".format(a.target, a.name)), 0)


def cmd_devtools(a):
    """devtools show|hide|expand|collapse|recorderOn|recorderOff|resetSignposts|export."""
    if not a.rest or a.rest[0] not in DEVTOOLS_ACTIONS:
        out({"error": "devtools ACTION", "actions": DEVTOOLS_ACTIONS}, 1)
    action = a.rest[0]
    command = "exportDiagnostics" if action == "export" else "devtools"
    args = [] if action == "export" else ["action=" + action]
    result = send(a, build_request(command, args, None))
    code = EXIT.get(result.get("status"), 4)
    if action == "export" and code == 0:
        name = result["data"]["name"]
        result["pulled"] = pull(a, "exports/" + name, "railmap-{}-{}".format(a.target, name))
    out(result, code)


def cmd_sweep(a):
    """A standard timed pass over every command family, identical on sim, mac and device.
    Needs an app started with `launch` (isolated store). Prints one JSON summary; exit 4 if any step failed."""
    steps = []

    def step(command, *pairs, required=True):
        result = send(a, build_request(command, list(pairs), None))
        data = result.get("data") or {}
        entry = {"step": command, "args": list(pairs), "status": result.get("status"),
                 "appMs": result.get("elapsedMs"), "roundTripMs": result.get("roundTripMs")}
        if result.get("error"):
            entry["error"] = result["error"][:300]
        for key in ("timings", "ms", "waitedMs", "trips", "merged"):
            if key in data:
                entry[key] = data[key]
        if command == "state" and isinstance(data, dict):
            entry["inventory"] = data.get("inventory")
            entry["memory"] = data.get("memory")
            entry["window"] = data.get("window")
            entry["signposts"] = [(s["name"], s["count"], s["maxMs"]) for s in
                                  (data.get("signposts") or {}).get("byName", [])[:12]]
        entry["required"] = required
        steps.append(entry)
        return result

    samples = a.rest[0] if a.rest else "tokyo-limited-express-loop"
    step("wait", "condition=mapReady", "timeoutMs=60000")
    step("state", "trips=false")
    step("loadSamples", "samples=" + samples)
    step("wait", "condition=routesLoaded", "timeoutMs=600000")
    first = send(a, build_request("state", [], None))
    trips = ((first.get("data") or {}).get("trips") or [])
    trip = trips[0]["id"] if trips else None
    if trip:
        step("selectTrip", "id=" + trip)
        step("focusTrip", "id=" + trip)
        step("screenshot", "name=sweep-selected")
        step("openEditor", "id=" + trip)
        step("cancelEditor")
    step("addTrip", "from=品川", "to=横浜", "date=2025-01-03", required=False)
    step("cancelEditor", required=False)
    step("openStats")
    step("setHideFilter", "years=[2025]")
    step("setHideFilter", "mode=showAll")
    step("setLayer", "name=metro", "on=false")
    step("setLayer", "name=metro", "on=true")
    step("reloadAll", "wait=true", "timeoutMs=600000")
    step("clearRouteCaches")
    step("memoryWarning")
    step("screenshot", "name=sweep-end")
    step("state", "trips=false")
    exported = send(a, build_request("exportDiagnostics", [], None))
    export = {"status": exported.get("status")}
    if exported.get("status") == "ok":
        name = exported["data"]["name"]
        export["pulled"] = pull(a, "exports/" + name, "railmap-{}-{}".format(a.target, name))
    failed = [s for s in steps if s["required"] and s["status"] != "ok"]
    out({"target": a.target, "device": device_id(a), "ok": not failed,
         "failedSteps": [s["step"] for s in failed], "steps": steps, "export": export}, 0 if not failed else 4)


SIZE_UNITS = {"K": 1 / 1024, "M": 1.0, "G": 1024.0, "T": 1024.0 * 1024}


def size_mb(token):
    """'208K' / '168.1M' / '1.0G' as megabytes (vmmap units are powers of 1024)."""
    match = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)([KMGT]?)", token)
    if not match:
        return None
    return float(match.group(1)) * (SIZE_UNITS[match.group(2)] if match.group(2) else 1 / 1048576)


def drawing_class(gpu_mb):
    """What the GPU row says about MapKit: run 4 (not drawing) 0.2 MB, run 5 (drawing) 168 MB."""
    if gpu_mb is None or gpu_mb < 1:
        return "none"
    if gpu_mb < 60:
        return "hidden"
    return "backlog" if gpu_mb > 400 else "drawing"


def parse_vmmap_summary(text):
    """Pure parse of `vmmap -summary` text: footprint, peak, app heap, GPU and MapKit pools (MB).

    appHeapMB is DefaultMallocZone bytes allocated, gpuMB the resident size of the
    'IOAccelerator (graphics)' region, mapKitMB the allocated bytes of the VectorKit* and Geo* zones.
    A missing row is None; `drawing` is classed from gpuMB (see drawing_class).
    """
    footprint = peak = gpu = heap = None
    map_kit = 0.0
    saw_map_kit = False
    for line in text.splitlines():
        stripped = line.strip()
        match = re.match(r"Physical footprint( \(peak\))?:\s+(\S+)", stripped)
        if match:
            if match.group(1):
                peak = size_mb(match.group(2))
            else:
                footprint = size_mb(match.group(2))
            continue
        match = re.match(r"IOAccelerator \(graphics\)\s+((?:\S+\s+){6}\S+)\s+\d+", stripped)
        if match:
            gpu = size_mb(match.group(1).split()[1])
            continue
        match = re.match(r"([A-Za-z]\w*?)_0x[0-9a-f]+\s+(.*)$", stripped)
        if match:
            fields = match.group(2).split()
            if len(fields) < 6:
                continue
            allocated = size_mb(fields[5])
            if allocated is None:
                continue
            name = match.group(1)
            if name == "DefaultMallocZone":
                heap = allocated
            elif name.startswith(("VectorKit", "Geo")):
                map_kit += allocated
                saw_map_kit = True
    return {"footprintMB": round_mb(footprint), "peakMB": round_mb(peak), "appHeapMB": round_mb(heap),
            "gpuMB": round_mb(gpu), "mapKitMB": round_mb(map_kit) if saw_map_kit else None,
            "drawing": drawing_class(gpu)}


def round_mb(value):
    return None if value is None else round(value, 1)


def cmd_memory_score(a):
    """memory-score FILE|-: score one `vmmap -summary` capture. Exit 4 when it is not a drawing app's."""
    if not a.rest:
        out({"error": "memory-score FILE (a `vmmap -summary` capture, or - for stdin)"}, 1)
    text = sys.stdin.read() if a.rest[0] == "-" else Path(a.rest[0]).read_text(errors="replace")
    score = parse_vmmap_summary(text)
    if score["gpuMB"] is None:
        out({"error": "no 'IOAccelerator (graphics)' row: not a vmmap -summary of the app", **score}, 4)
    if score["drawing"] == "none":
        out({"error": "GPU row under 1 MB: MapKit was not drawing, so the memory number is not comparable", **score}, 4)
    out(score, 0)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--target", choices=["sim", "mac", "device"], default="sim")
    ap.add_argument("--device", help="simulator or device UDID (defaults: iPhone 17 sim / iPhone 16 Pro)")
    ap.add_argument("--app", help="built RailMap.app (default: " + str(DERIVED) + "/Build/Products/<config>)")
    ap.add_argument("--allow-dirty", action="store_true",
                    help="launch (mac) a build stamped -dirty, made from uncommitted changes")
    ap.add_argument("--timeout", type=float, default=None,
                    help="seconds to wait for a result (default per command, at least the app's own timeout)")
    ap.add_argument("--transport", choices=["poll", "url", "file"], default="poll",
                    help="poll (default): inbox file, picked up by the app's poller (needs `launch`); "
                         "url / file: also open a railmap-test:// URL, which iOS 26+ confirms with an "
                         "'Open in RailMap?' prompt that needs a tap")
    ap.add_argument("--json", help="extra args as one JSON object")
    ap.add_argument("--storage", help="launch: isolated storage UUID or 'new' (default new)")
    ap.add_argument("--env", action="append", help="launch: extra KEY=VALUE for the app")
    ap.add_argument("--no-devtools", action="store_true", help="launch: hide the developer ball (RAILMAP_DEVTOOLS=0)")
    ap.add_argument("--out", help="pull-screenshot / devtools export: destination file")
    ap.add_argument("--jobs", type=int, default=2, help="build: xcodebuild -jobs")
    ap.add_argument("--configuration", choices=["Debug", "Release"], default="Debug",
                    help="build/install/launch: product configuration (Release only for check-release)")
    ap.add_argument("--dry-run", action="store_true", help="build: print the xcodebuild command")
    ap.add_argument("--data-only", action="store_true", help="print only the result's data on success")
    ap.add_argument("action", help="a command, or build|install|launch|terminate|ready|pull-screenshot|devtools|check-release|sweep|memory-score")
    ap.add_argument("rest", nargs="*", help="key=value args (or the screenshot name for pull-screenshot)")
    a = ap.parse_args()

    if a.action == "build":
        cmd_build(a)
    if a.action == "memory-score":
        cmd_memory_score(a)
    if a.action == "check-release":
        cmd_check_release(a)
    if a.action == "sweep":
        cmd_sweep(a)
    if a.action == "install":
        cmd_install(a)
    if a.action == "launch":
        cmd_launch(a)
    if a.action == "terminate":
        terminate(a)
        out({"terminated": True}, 0)
    if a.action == "ready":
        cmd_ready(a)
    if a.action == "pull-screenshot":
        if not a.rest:
            out({"error": "pull-screenshot NAME"}, 1)
        a.name = a.rest[0]
        cmd_pull(a)
    if a.action == "devtools" and (not a.rest or "=" not in a.rest[0]):
        cmd_devtools(a)
    if a.action not in COMMANDS:
        out({"error": "unknown action", "action": a.action, "commands": COMMANDS}, 1)
    result = send(a, build_request(a.action, a.rest, a.json))
    code = EXIT.get(result.get("status"), 4)
    if a.data_only and code == 0:
        out(result.get("data"), 0)
    out(result, code)


if __name__ == "__main__":
    main()
