"""Replay prepared public fixtures through the unchanged native ASR on an emulator.

Requires native_asr_benchmark, Tiny model.bin and packaged ARM64 libraries in
/data/local/tmp/sulti-eval. This measures the baseline; platform microphone
suppression cannot process these prerecorded buffers. No accuracy gain claimed.
"""
import argparse
import json
from pathlib import Path
import subprocess
from score_asr import score


def run(adb, device, fixtures, output):
    remote = '/data/local/tmp/sulti-eval'
    prefix = [str(adb), '-s', device]
    subprocess.run(prefix + ['push', str(fixtures), remote + '/'], check=True,
                   capture_output=True)
    rows = []
    for fixture in json.loads((fixtures / 'manifest.json').read_text()):
        # Filenames come from the generated manifest; refuse shell metacharacters.
        name = fixture['file']
        if any(c not in 'abcdefghijklmnopqrstuvwxyz0123456789-_. ' for c in name) or ' ' in name:
            raise ValueError('Unexpected fixture name')
        command = (f'cd {remote} && LD_LIBRARY_PATH=. ./native_asr_benchmark '
                   f'model.bin noise-fixtures/{name} tl 4')
        process = subprocess.run(prefix + ['shell', command], check=True,
                                 capture_output=True, text=True, timeout=90)
        result = json.loads(process.stdout)
        row = dict(fixture, raw=result['text'], corrected=result['text'],
                   processing_ms=result['processing_us']/1000)
        rows.append(row)
        print(f'{fixture["id"]}: {row["processing_ms"]:.0f} ms', flush=True)
    report = {'scope': 'Unchanged Tiny on emulator; synthetic noise, no platform suppression',
              'device': device, 'rows': rows, 'by_condition': {}}
    for condition in sorted({row['style'] for row in rows}):
        subset = [row for row in rows if row['style'] == condition]
        report['by_condition'][condition] = score(subset)
    output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb', type=Path, required=True)
    parser.add_argument('--device', default='emulator-5554')
    parser.add_argument('--fixtures', type=Path, default=Path('evaluation/private/noise-fixtures'))
    parser.add_argument('--output', type=Path, default=Path('benchmarks/noise-diagnostic-results.json'))
    args = parser.parse_args()
    run(args.adb, args.device, args.fixtures, args.output)
