"""Create reproducible noise stress inputs from existing licensed float32 fixtures.

These synthetic mixtures are a diagnostic baseline, not real-room evidence of
NoiseSuppressor quality. No VAD, trimming, normalization or denoising is applied
by the app. Never overwrite original recordings.
"""
import argparse
import json
from pathlib import Path
import numpy as np


def prepare(directory):
    output = directory / 'noise-fixtures'
    output.mkdir(exist_ok=True)
    records = []
    for fixture in json.loads((directory / 'fil-fixtures.json').read_text()):
        original = np.fromfile(directory / (fixture['filename'] + '.f32'), dtype='<f4')
        rng = np.random.default_rng(20261009)
        noise = rng.normal(size=len(original))
        # Stationary broad-band noise plus hum; do not label as recorded traffic.
        noise += .3 * np.sin(np.arange(len(original)) * 2 * np.pi * 60 / 16000)
        noise /= np.sqrt(np.mean(noise ** 2))
        rms = np.sqrt(np.mean(original ** 2))
        cases = {'clean': original,
                 'moderate_10db': original + noise * rms / np.sqrt(10),
                 'loud_0db': original + noise * rms,
                 'changing_noise': original + noise * rms * np.linspace(.1, 1.5, len(original)),
                 'quiet_noisy': original * .1 + noise * rms * .1,
                 'pauses': np.concatenate([np.zeros(8000), original[:len(original)//2],
                                           np.zeros(16000), original[len(original)//2:], np.zeros(8000)])}
        for condition, samples in cases.items():
            samples = np.asarray(samples, dtype=np.float32)
            # Mix headroom only, not the app's preprocessing. Clean PCM is exact.
            peak = float(np.max(np.abs(samples)))
            scale = min(1., .98 / peak) if condition != 'clean' and peak else 1.
            samples *= scale
            name = f'{fixture["id"]}-{condition}.f32'
            samples.astype('<f4').tofile(output / name)
            records.append({'id': f'{fixture["id"]}-{condition}', 'file': name,
                'speaker': 'public-fleurs-' + fixture['id'], 'style': condition,
                'reference': fixture['reference'], 'seconds': len(samples)/16000,
                'mix_scale': scale, 'seed': 20261009})
    (output / 'manifest.json').write_text(json.dumps(records, indent=2) + '\n')
    print(f'Wrote {len(records)} public diagnostic fixtures in {output}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path, nargs='?', default=Path('evaluation/private'))
    prepare(parser.parse_args().directory)
