#!/usr/bin/env python3
"""Measure the fixed two-region Release route phase with paired fresh processes.

Usage: python3 measure-release-route-memory.py --baseline-dd BEFORE_DD \
  --candidate-dd AFTER_DD --fixture fixtures/release-route-memory-two-regions.json \
  --device OWNED_SIMULATOR_UUID --output results.json [--trials 3]

Uses existing Release build-for-testing products; never builds. Only a dedicated
JTMRefactor* simulator is permitted. The public XCTest must prove both real
routes, global load completion, Stats readiness and All regions before holding
for sampling. Scope is this JP/TW fixture and phase pair, not national/full-app
memory acceptance. Physical footprint/peak are distinct from RSS. A passing
gate requires strictly lower median settled footprint and nonincreased median
process peak; functional success alone is not a reduction.
"""
from collections import deque
from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import shutil
import signal
import statistics
import subprocess
import time

BUNDLE_ID = 'com.JRM.RailMap'
BUDGET = 2 * 1024**3
TEST = 'RailMapUITests/RefactorReleaseMemoryUITests/testTwoRealRegionsCompleteRoutesAndStatistics'


def command(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def text_command(args):
    return subprocess.check_output(args, text=True).strip()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def products(dd):
    folder = dd.resolve() / 'Build/Products'
    runs = [p for p in folder.glob('*.xctestrun') if 'opt-in' not in p.name]
    if len(runs) != 1:
        raise ValueError(f'{folder}: expected one original xctestrun, found {len(runs)}')
    configuration = plistlib.loads(runs[0].read_bytes())
    targets = [target for item in configuration.get('TestConfigurations', [])
               for target in item.get('TestTargets', [])
               if target.get('BlueprintName') == 'RailMapUITests']
    if not targets and isinstance(configuration.get('RailMapUITests'), dict):
        targets = [configuration['RailMapUITests']]
    if len(targets) != 1:
        raise ValueError('Expected one RailMapUITests target')
    target = targets[0]
    app = folder / 'Release-iphonesimulator/RailMap.app'
    host = folder / 'Release-iphonesimulator/RailMapUITests-Runner.app'
    expected = str(app)
    target_app = target.get('UITargetAppPath', '').replace('__TESTROOT__', str(folder))
    target_host = target.get('TestHostPath', '').replace('__TESTROOT__', str(folder))
    if target_app != expected or target_host != str(host):
        raise ValueError('xctestrun must reference the matching Release simulator app/runner')
    for path in [app / 'RailMap', host / 'PlugIns/RailMapUITests.xctest']:
        if not path.exists():
            raise ValueError(f'Missing Release product: {path}')
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != BUNDLE_ID:
        raise ValueError('Unexpected app bundle identifier')
    for key in ['EnvironmentVariables', 'TestingEnvironmentVariables', 'UITargetAppEnvironmentVariables']:
        if any(name.startswith('RAILMAP_') for name in target.get(key, {})):
            raise ValueError('Release measurement must not enable DEBUG app/test hooks')
    return app, runs[0]


def dedicated_device(identifier):
    inventory = json.loads(text_command(['xcrun', 'simctl', 'list', 'devices', '--json']))
    matches = [d for group in inventory['devices'].values() for d in group
               if d.get('udid') == identifier]
    if len(matches) != 1 or not matches[0].get('isAvailable'):
        raise ValueError('Explicit simulator UUID must identify one available device')
    device = matches[0]
    if not device['name'].startswith('JTMRefactor'):
        raise ValueError('Measurement requires a dedicated simulator named JTMRefactor*')
    return device


def find_owned_pid(device, executable):
    pids = []
    for row in text_command(['ps', '-axo', 'pid,args']).splitlines()[1:]:
        fields = row.strip().split(None, 1)
        if len(fields) == 2 and device in fields[1] and str(executable) in fields[1]:
            pids.append(int(fields[0]))
    if len(pids) > 1:
        raise ValueError('More than one matching owned app PID; no paired acceptance')
    return pids[0] if pids else None


def footprint(pid, path):
    # Remove only this run's prior temporary sample so a failed invocation
    # cannot accidentally reuse stale data.
    path.unlink(missing_ok=True)
    result = subprocess.run(['footprint', '-p', str(pid), '--noCategories', '-f', 'bytes',
                             '-j', str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if result.returncode or not path.exists():
        return None
    matches = [p for p in json.loads(path.read_text()).get('processes', [])
               if p.get('pid') == pid]
    if len(matches) != 1:
        raise ValueError('Footprint response does not identify the owned app PID')
    auxiliary = matches[0].get('auxiliary', {})
    current, peak = auxiliary.get('phys_footprint'), auxiliary.get('phys_footprint_peak')
    if not isinstance(current, (int, float)) or not isinstance(peak, (int, float)) or current <= 0 or peak < current:
        raise ValueError('Actual physical footprint and process peak are unavailable')
    return {'pid': pid, 'current_bytes': current, 'peak_bytes': peak, 'time': time.time()}


def persist(path, result):
    path.write_text(json.dumps(result, indent=2) + '\n')


def run_trial(label, trial, app, xctestrun, fixture, device, output, record):
    prefix = output.parent / f'{output.stem}-{label}-{trial}'
    record.update(label=label, trial=trial, fixture_sha256=sha(fixture),
                  app_binary_sha256=sha(app / 'RailMap'), xctestrun_sha256=sha(xctestrun),
                  samples_path=str(prefix) + '-samples.jsonl', budget_stopped=False)
    # Fresh only this explicit app on the verified dedicated simulator.
    for operation in ['terminate', 'uninstall']:
        subprocess.run(['xcrun', 'simctl', operation, device, BUNDLE_ID],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    command(['xcrun', 'simctl', 'install', device, str(app)])
    container = Path(text_command(['xcrun', 'simctl', 'get_app_container', device, BUNDLE_ID, 'data'])).resolve()
    if device not in str(container) or 'Containers/Data/Application' not in str(container):
        raise ValueError('App data container does not belong to the explicit simulator')
    installed_app = Path(text_command(['xcrun', 'simctl', 'get_app_container', device, BUNDLE_ID, 'app'])).resolve()
    if device not in str(installed_app) or installed_app.name != 'RailMap.app':
        raise ValueError('Installed executable ownership is not established')
    store = container / 'Library/Application Support/Rides/train-store.json'
    store.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(fixture, store)
    if sha(store) != record['fixture_sha256']:
        raise ValueError('Seeded fixture differs from the supplied source')
    args = ['xcodebuild', 'test-without-building', '-xctestrun', str(xctestrun),
            '-destination', 'platform=iOS Simulator,id=' + device,
            '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never',
            '-only-testing:' + TEST, '-resultBundlePath', str(prefix) + '.xcresult']
    record['command'] = args
    recent = deque(maxlen=5)
    count, peak, owned_pid = 0, 0, None
    runner = None
    try:
        with open(str(prefix) + '.log', 'w') as log, open(record['samples_path'], 'w') as samples:
            runner = subprocess.Popen(args, stdout=log, stderr=subprocess.STDOUT)
            while runner.poll() is None:
                pid = find_owned_pid(device, installed_app / 'RailMap')
                if pid is not None:
                    if owned_pid is not None and owned_pid != pid:
                        raise ValueError('App PID changed during one measurement trial')
                    owned_pid = pid
                    sample = footprint(pid, Path(str(prefix) + '-footprint.json'))
                    if sample:
                        samples.write(json.dumps(sample) + '\n'); samples.flush()
                        count += 1; recent.append(sample['current_bytes'])
                        peak = max(peak, sample['peak_bytes'])
                        if peak > BUDGET:
                            runner.send_signal(signal.SIGSTOP)
                            subprocess.run(['xcrun', 'simctl', 'terminate', device, BUNDLE_ID],
                                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                            runner.terminate(); runner.send_signal(signal.SIGCONT)
                            record['budget_stopped'] = True
                            break
                time.sleep(1)
            record['exit'] = runner.wait()
    finally:
        if runner is not None and runner.poll() is None:
            runner.terminate()
            runner.wait()
        record.update(pid=owned_pid, sample_count=count, peak_bytes=peak,
                      settled_bytes=statistics.median(recent) if len(recent) == 5 else None)
    if record['exit'] or record['budget_stopped'] or len(recent) < 5:
        raise ValueError('Public physical-route/UI proof or valid sampling failed; no paired acceptance')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['baseline-dd', 'candidate-dd', 'fixture', 'output']:
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--device', required=True)
    parser.add_argument('--trials', type=int, default=3)
    args = parser.parse_args()
    if args.trials <= 0:
        parser.error('--trials must be positive')
    args.output = args.output.resolve()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    result = {'complete': False, 'completed_all_trials': False, 'gate_pass': False,
              'protocol': {'trials_per_build': args.trials, 'order': ['baseline', 'candidate'] * args.trials,
                           'device': args.device, 'budget_bytes': BUDGET,
                           'metric': 'actual physical footprint; settled median of final five samples',
                           'gate': 'candidate median settled strictly lower; median process peak no increase',
                           'scope': 'exact real JP Sonic44 + TW airport MRT; route phase pair only',
                           'ready': 'global Routes loaded; both exact public Route generated details; Stats ready; All regions',
                           'configuration': 'Release; fresh app container/process; no DEBUG hooks'}, 'runs': []}
    persist(args.output, result)
    try:
        fixture = args.fixture.resolve()
        reference = Path(__file__).parent / 'fixtures/release-route-memory-two-regions.json'
        if json.loads(fixture.read_text()) != json.loads(reference.read_text()):
            raise ValueError('Fixture must equal the reviewed committed two-region records; no synthetic confirmations/geometry')
        result['protocol']['fixture_sha256'] = sha(fixture)
        device = dedicated_device(args.device)
        result['protocol']['device_name'] = device['name']
        builds = {'baseline': products(args.baseline_dd), 'candidate': products(args.candidate_dd)}
        if device['state'] != 'Booted':
            command(['xcrun', 'simctl', 'boot', args.device])
        command(['xcrun', 'simctl', 'bootstatus', args.device, '-b'], stdout=subprocess.DEVNULL)
        for trial in range(1, args.trials + 1):
            for label in ['baseline', 'candidate']:
                record = {}; result['runs'].append(record)
                if sha(fixture) != result['protocol']['fixture_sha256']:
                    raise ValueError('Supplied fixture changed between paired trials')
                run_trial(label, trial, *builds[label], fixture, args.device, args.output, record)
                persist(args.output, result)
                print(label, trial, record['settled_bytes'], record['peak_bytes'], flush=True)
        baseline = [r for r in result['runs'] if r['label'] == 'baseline']
        candidate = [r for r in result['runs'] if r['label'] == 'candidate']
        b = statistics.median(r['settled_bytes'] for r in baseline)
        c = statistics.median(r['settled_bytes'] for r in candidate)
        bp = statistics.median(r['peak_bytes'] for r in baseline)
        cp = statistics.median(r['peak_bytes'] for r in candidate)
        result.update(completed_all_trials=True, baseline_median_settled_bytes=b,
                      candidate_median_settled_bytes=c, baseline_median_peak_bytes=bp,
                      candidate_median_peak_bytes=cp, settled_reduction_percent=100*(b-c)/b,
                      peak_reduction_percent=100*(bp-cp)/bp, gate_pass=c < b and cp <= bp)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        result['error'] = str(error)
    finally:
        result['complete'] = True
        persist(args.output, result)
    print(json.dumps({k: v for k, v in result.items() if k not in ['runs', 'protocol']}), flush=True)
    return 0 if result['gate_pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
