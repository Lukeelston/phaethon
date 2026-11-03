"""Bounded regression set for the release; keep per-test evidence."""
from pathlib import Path
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
TESTS = [
    'test_parity', 'test_range_parity', 'test_sprint_parity',
    'test_gp_parity', 'test_handling_parity', 'test_mode_parity',
    'test_network_parity', 'test_brakes', 'test_energy',
    'test_quest_controls', 'test_controls_flyable', 'test_xr_focus',
    'test_mode_switch', 'test_track_switch', 'test_dashboard',
    'test_release_input', 'test_release_menu', 'test_release_vr', 'test_vr_menu',
    'test_mode_gears',
]
results = []
for name in TESTS:
    result = subprocess.run([
        sys.executable, str(ROOT/'tools/run_godot.py'),
        'gearing-'+name+'.log', '180' if name == 'test_energy' else '90', '--headless', '--xr-mode', 'off',
        '--audio-driver', 'Dummy', '--path', 'godot', '-s',
        'res://tests/'+name+'.gd', '--', '--mute',
    ], cwd=ROOT, capture_output=True, text=True)
    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        data = {'runner_output': result.stdout, 'stderr': result.stderr}
    row = {'test': name, 'passed': result.returncode == 0 and not data.get('errors'), 'result': data}
    results.append(row)
    print(json.dumps({'test': name, 'passed': row['passed'], 'errors': data.get('errors', [])}), flush=True)
(ROOT/'evidence/gearing-regressions.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
raise SystemExit(int(any(not row['passed'] for row in results)))
