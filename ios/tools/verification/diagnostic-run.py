#!/usr/bin/env python3
"""Drive the Rail Diagnostics Mac Catalyst app from an agent shell (stdlib only).

capture/send write or take a request, open it in the app, then wait for the
requestID-matched run-status.json, or a rejection record. Exit: 0 ok, 2 rejected,
3 timeout, 4 failed. Does not build the app; one native job at a time.
"""
import argparse, datetime, json, os, re, subprocess, sys, tempfile, time
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
EXTERNAL_VOLUME = Path("/Volumes/JTM Evidence")
EXTERNAL_ROOT = EXTERNAL_VOLUME / "99 Compatibility/Workspace/JTM-iOS-App/railway-evidence/local"
EVIDENCE = Path(os.environ.get("RAILWAY_EVIDENCE_ROOT") or EXTERNAL_ROOT)
DEFAULT_APP = os.path.expanduser("~/Library/Caches/jtm-rail-diagnostics/Build/Products/Debug-maccatalyst/RailDiagnostics.app")  # /private/tmp is wiped on reboot
OK_STATES = {"evidenceReady", "prepared"}



def require_write_path(path):
    """Resolve compatibility links before writes; never create a mount fallback."""
    path = Path(path)
    if not path.is_absolute():
        raise ValueError("Evidence write paths must be absolute.")
    resolved = path.resolve()
    def inside(root):
        return resolved == root or root in resolved.parents
    scratch = (Path("/private/tmp"), Path(tempfile.gettempdir()).resolve())
    if any(inside(root) for root in scratch):
        return resolved
    if not inside(EXTERNAL_ROOT):
        raise ValueError("Evidence writes require the external archive or explicit private scratch: " + str(path))
    if not EXTERNAL_VOLUME.is_mount():
        raise ValueError("Mount the external railway evidence archive at /Volumes/JTM Evidence before writing evidence.")
    return resolved


def out(obj, code):
    print(json.dumps(obj, ensure_ascii=False, separators=(",", ":")))
    sys.exit(code)


def read_json(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def slug(text):
    s = re.sub(r"[^0-9A-Za-z]+", "-", text).strip("-").lower()
    return s or "line"


def build_request(a):
    now = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    ivs = [int(x) for x in a.intervals.split(",")] if a.intervals else None
    name = a.name or "{}-{}-z{}-{}".format(
        slug(a.line), "i" + "-".join(map(str, ivs)) if ivs else "all", a.zoom, now)
    w, h = (int(x) for x in a.size.lower().split("x"))
    req = {"schemaVersion": 1, "requestID": name, "workspace": "alignment", "action": a.action,
           "sessionDirectory": str(EVIDENCE / "diagnostics/sessions" / name), "lineID": a.line}
    if ivs: req["intervalIndices"] = ivs
    if a.stations: req["stationIDs"] = a.stations.split(",")
    if a.viewpoints: req["viewpointIDs"] = a.viewpoints.split(",")
    if a.input: req["inputPath"] = a.input
    req["captureSettings"] = {"appearance": a.appearance, "basemapStyle": a.basemap, "height": h,
                              "outputModes": a.modes.split(","), "width": w, "zoom": a.zoom}
    return name, req


def rejection_count(log):
    try:
        return len(Path(log).read_text(encoding="utf-8").splitlines())
    except OSError:
        return 0


def session_views(session, interval=None):
    idx = read_json(Path(session) / "capture-index.json") or {}
    views = []
    for v in idx.get("views", []):
        item = v.get("itemID", "")
        iv = item.rsplit("#", 1)[-1]
        vid = v.get("viewpointID") or "{}#point-{}".format(item, v.get("pointOrdinal", 0))
        if interval is not None and iv != str(interval):
            continue
        views.append({"viewpointID": vid, "directory": v.get("directory")})
    return views


def summarize(req_id, session, status, result):
    r = result or {}
    return {"requestID": req_id, "state": status.get("state"), "message": status.get("message"),
            "capturedCount": r.get("capturedCount"), "failedCount": r.get("failedCount"),
            "pendingCount": r.get("pendingCount"), "invocationID": status.get("invocationID"),
            "processID": status.get("processID"), "sessionDirectory": str(session),
            "views": session_views(session)}


def send_and_wait(req_path, req, timeout, app):
    try:
        require_write_path(req["sessionDirectory"])
        if req.get("alignmentEvidenceDirectory"):
            require_write_path(req["alignmentEvidenceDirectory"])
        require_write_path(EVIDENCE / "diagnostics/inbox/rejections.jsonl")
    except (OSError, ValueError) as error:
        out({"rejected": True, "reason": str(error)}, 2)
    session = Path(req["sessionDirectory"])
    req_id = req["requestID"]
    log = EVIDENCE / "diagnostics/inbox/rejections.jsonl"
    before = rejection_count(log)
    started = time.time()
    r = subprocess.run(["open", "-a", app, str(req_path)], capture_output=True, text=True)
    if r.returncode != 0:
        out({"rejected": False, "state": "openFailed", "reason": r.stderr.strip()}, 4)
    deadline = started + timeout
    while time.time() < deadline:
        lines = []
        try:
            lines = Path(log).read_text(encoding="utf-8").splitlines()[before:]
        except OSError:
            pass
        for line in lines:
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if rec.get("requestID") == req_id or rec.get("requestPath") == str(req_path):
                out({"rejected": True, "reason": rec.get("reason"), "requestID": req_id}, 2)
        lr = session / "last-rejection.json"
        if lr.exists() and lr.stat().st_mtime >= started - 1:
            rec = read_json(lr) or {}
            out({"rejected": True, "reason": rec.get("reason"), "requestID": req_id}, 2)
        st = read_json(session / "run-status.json")
        if st and st.get("requestID") == req_id and st.get("active") is False:
            res = read_json(session / "result.json")
            if res and res.get("requestID") != req_id:
                res = None
            summary = summarize(req_id, session, st, res)
            out(summary, 0 if st.get("state") in OK_STATES else 4)
        time.sleep(2)
    st = read_json(session / "run-status.json") or {}
    out({"requestID": req_id, "state": "timeout", "message": st.get("message"),
         "lastState": st.get("state"), "sessionDirectory": str(session)}, 3)


def resolve_session(arg):
    p = Path(arg)
    return p if p.is_absolute() or p.exists() else EVIDENCE / "diagnostics/sessions" / arg


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("capture", help="build an alignment request, send it, wait")
    c.add_argument("--line", required=True)
    c.add_argument("--intervals"); c.add_argument("--stations"); c.add_argument("--viewpoints")
    c.add_argument("--zoom", type=int, default=19)
    c.add_argument("--size", default="2400x2000")
    c.add_argument("--appearance", default="light")
    c.add_argument("--basemap", default="standard")
    c.add_argument("--modes", default="basemap,smooth")
    c.add_argument("--input"); c.add_argument("--name")
    c.add_argument("--action", default="capture", choices=["capture", "prepare"])
    c.add_argument("--dry-run", action="store_true", help="print the request; write and open nothing")
    s = sub.add_parser("send", help="send an existing absolute request.json")
    s.add_argument("request")
    for p in (c, s):
        p.add_argument("--timeout", type=int, default=900)
        p.add_argument("--app", default=DEFAULT_APP)
    st = sub.add_parser("status", help="show run-status.json and result counts")
    st.add_argument("session")
    v = sub.add_parser("views", help="list captured views from capture-index.json")
    v.add_argument("session"); v.add_argument("--interval", type=int)
    a = ap.parse_args()

    if a.cmd == "capture":
        name, req = build_request(a)
        session = Path(req["sessionDirectory"])
        if a.dry_run:
            print(json.dumps(req, ensure_ascii=False, indent=2)); return
        if session.exists():
            out({"rejected": True, "reason": "Session directory exists: {}. action and requestID are part of "
                 "request identity, so a changed request is refused; use a new --name.".format(session)}, 2)
        try:
            require_write_path(session)
            path = require_write_path(EVIDENCE / "requests" / (name + ".json"))
        except (OSError, ValueError) as error:
            out({"rejected": True, "reason": str(error)}, 2)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(req, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        send_and_wait(path, req, a.timeout, a.app)
    elif a.cmd == "send":
        path = Path(a.request)
        req = read_json(path)
        if not path.is_absolute() or not isinstance(req, dict) or "requestID" not in req or "sessionDirectory" not in req:
            out({"rejected": True, "reason": "Need an absolute readable request.json with requestID and sessionDirectory."}, 2)
        send_and_wait(path, req, a.timeout, a.app)
    elif a.cmd == "status":
        session = resolve_session(a.session)
        stt = read_json(session / "run-status.json")
        if not stt:
            out({"state": "none", "sessionDirectory": str(session)}, 4)
        summary = summarize(stt.get("requestID"), session, stt, read_json(session / "result.json"))
        summary["active"] = stt.get("active")
        out(summary, 0)
    else:
        session = resolve_session(a.session)
        out({"sessionDirectory": str(session), "views": session_views(session, a.interval)}, 0)


if __name__ == "__main__":
    main()
