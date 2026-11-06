#!/usr/bin/env python3
"""Drive the DEBUG RailMap app (com.JRM.RailMap) without touching the screen (stdlib only; run with -I).

  app-control.py --target sim|mac|device [--device UDID] COMMAND [key=value ...] [--json '{...}']
  app-control.py --target T build|install|launch|terminate|ready|pull-screenshot ...

Commands go to the app's test control channel (DEBUG builds only): a railmap-test://run URL
(inline request, or ?request=<id> naming inbox/<id>.json in the app container). The app runs the
command through its own stores and views and writes results/result-<id>.json, which this tool waits
for by request ID and prints as one compact JSON line.

Commands: loadSamples useStorage reloadAll state selectTrip focusTrip openEditor addTrip editTrip
saveEditor cancelEditor deleteTrip openStats setHideFilter screenshot wait.
Values parse as JSON when they can (numbers, true/false, [..], {..}); otherwise they are strings.

Exit: 0 ok, 2 rejected (bad request, or refused because the app is on the shared store),
3 timeout, 4 failed, 1 tool/usage error. One native app job at a time across all chats.
"""
import argparse, base64, json, os, shutil, subprocess, sys, tempfile, time, uuid
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
BUNDLE = "com.JRM.RailMap"
SCHEME = "railmap-test"
ROOT_NAME = "RailMapAppControl"
CONTAINER_ROOT = "Library/Application Support/" + ROOT_NAME
DEFAULT_SIM = "0DBE2488-0BEB-4932-9B55-091B3CC793B6"
DEFAULT_DEVICE = "00008140-000575142288801C"
DERIVED = Path(os.path.expanduser("~/Library/Caches/jtm-railmap-app-control/DerivedData"))
PLATFORM_SUFFIX = {"sim": "iphonesimulator", "mac": "maccatalyst", "device": "iphoneos"}
DESTINATIONS = {"sim": "platform=iOS Simulator,id={device}", "mac": "platform=macOS,variant=Mac Catalyst",
                "device": "platform=iOS,id={device}"}
STATE_DIR = Path(os.path.expanduser("~/Library/Caches/jtm-railmap-app-control"))
COMMANDS = ["loadSamples", "useStorage", "reloadAll", "state", "selectTrip", "focusTrip", "openEditor",
            "addTrip", "editTrip", "saveEditor", "cancelEditor", "deleteTrip", "openStats", "setHideFilter",
            "screenshot", "wait", "devtools", "exportDiagnostics", "clearRouteCaches", "memoryWarning", "setLayer"]
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
        out({"error": "command failed", "cmd": cmd, "code": p.returncode,
             "stderr": (p.stderr or "")[-2000:], "stdout": (p.stdout or "")[-1000:]}, 1)
    return p


def device_id(a):
    return a.device or (DEFAULT_SIM if a.target == "sim" else DEFAULT_DEVICE if a.target == "device" else "mac")


def app_path(a):
    if a.app:
        return Path(a.app)
    return DERIVED / "Build/Products" / "{}-{}".format(a.configuration, PLATFORM_SUFFIX[a.target]) / "RailMap.app"


def state_file(a):
    return STATE_DIR / "{}-{}.json".format(a.target, device_id(a))


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
        # On a device the copy is not atomic: write `.req`, which only the URL (not the poller) reads.
        suffix = "req" if a.target == "device" and a.transport != "poll" else "json"
        write_container_file(a, "inbox/{}.{}".format(rid, suffix), payload)
        if a.transport != "poll":
            open_url(a, "{}://run?request={}".format(SCHEME, rid))
    timeout = a.timeout if a.timeout is not None else DEFAULT_WAIT.get(request["command"], 90)
    args_timeout = request["args"].get("timeoutMs")
    if isinstance(args_timeout, (int, float)):
        timeout = max(timeout, args_timeout / 1000 + 10)
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
           "-jobs", str(a.jobs), "build"]
    if a.target != "device":
        cmd.append("CODE_SIGN_IDENTITY=-")  # ad-hoc: no team identity needed for sim or Catalyst
    else:
        cmd.append("-allowProvisioningUpdates")
    if a.dry_run:
        out({"cmd": cmd}, 0)
    p = run(cmd, check=False, timeout=3600)
    tail = [l for l in (p.stdout or "").splitlines() if "error:" in l or "BUILD" in l][-20:]
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


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--target", choices=["sim", "mac", "device"], default="sim")
    ap.add_argument("--device", help="simulator or device UDID (defaults: iPhone 17 sim / iPhone 16 Pro)")
    ap.add_argument("--app", help="built RailMap.app (default: " + str(DERIVED) + "/Build/Products/<config>)")
    ap.add_argument("--timeout", type=float, default=None,
                    help="seconds to wait for a result (default per command, at least the app's own timeout)")
    ap.add_argument("--transport", choices=["url", "file", "poll"], default="url",
                    help="url: inline URL (file+URL when large); file: inbox file + URL; poll: inbox file only")
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
    ap.add_argument("action", help="a command, or build|install|launch|terminate|ready|pull-screenshot|devtools|check-release")
    ap.add_argument("rest", nargs="*", help="key=value args (or the screenshot name for pull-screenshot)")
    a = ap.parse_args()

    if a.action == "build":
        cmd_build(a)
    if a.action == "check-release":
        cmd_check_release(a)
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
