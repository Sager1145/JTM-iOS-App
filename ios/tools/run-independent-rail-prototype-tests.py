#!/usr/bin/env python3
"""Explicitly opt into experimental map projection UI tests.
Writes only a derived .xctestrun copy; the shared Xcode scheme stays unchanged.
Accuracy assertions remain frozen and failures represent experiment NO-GO.
"""
from pathlib import Path
import argparse
import plistlib
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--destination', required=True, help='Xcode destination for the reserved simulator')
parser.add_argument('--derived-data', type=Path, default=Path('/tmp/jtm-independent-rail-build'))
parser.add_argument('--skip-build', action='store_true', help='Use an already generated current-source test build')
parser.add_argument('--case', action='append', default=[], help='Optional test method name; default is all experiment cases')
arguments = parser.parse_args()
root = Path(__file__).resolve().parents[2]
if not arguments.skip_build:
    subprocess.run(['xcodebuild', '-project', str(root / 'ios/RailMap.xcodeproj'), '-scheme', 'RailMap',
                '-configuration', 'Debug', '-destination', arguments.destination,
                '-derivedDataPath', str(arguments.derived_data), 'CODE_SIGNING_ALLOWED=NO',
                'build-for-testing'], check=True)
products = arguments.derived_data / 'Build/Products'
candidates = [file for file in products.glob('*.xctestrun') if file.name != 'independent-rail-opt-in.xctestrun']
if not candidates:
    raise SystemExit('Xcode did not produce an .xctestrun file')
original = max(candidates, key=lambda file: file.stat().st_mtime)
configuration = plistlib.loads(original.read_bytes())
targets = []
for test_configuration in configuration.get('TestConfigurations', []):
    targets.extend(target for target in test_configuration.get('TestTargets', [])
                   if target.get('BlueprintName') == 'RailMapUITests')
# Xcode also generates the legacy target-keyed schema when no test plan exists.
if not targets and isinstance(configuration.get('RailMapUITests'), dict):
    targets.append(configuration['RailMapUITests'])
for target in targets:
    target.setdefault('EnvironmentVariables', {})['RAILMAP_RUN_INDEPENDENT_RAIL_PROTOTYPE'] = '1'
count = len(targets)
if not count:
    raise SystemExit('No RailMapUITests runner in generated test configuration')
# Keep __TESTROOT__ relative to Products, where Xcode generated the bundle paths.
opt_in = products / 'independent-rail-opt-in.xctestrun'
opt_in.write_bytes(plistlib.dumps(configuration))
selected = arguments.case or ['']
filters = ['-only-testing:RailMapUITests/MapIndependentRailPrototypeUITests' + ('/' + case if case else '')
           for case in selected]
subprocess.run(['xcodebuild', '-xctestrun', str(opt_in), '-destination', arguments.destination,
                '-parallel-testing-enabled', 'NO', *filters, 'test-without-building'], check=True)
