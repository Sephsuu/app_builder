"""Download the pinned NLLB test artifacts, verify SHA-256, and retain resumable parts.

Development only. The Android app has its own explicit, serial setup download.
Uses bounded parallel range reads for hosts with slow long-lived CDN streams.
"""
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import urllib.request


def fetch(manifest, destination, workers=8):
    destination.mkdir(parents=True, exist_ok=True)
    for asset in manifest['files']:
        name = Path(asset['path']).name
        target = destination / name
        if target.exists() and digest(target) == asset['sha256']:
            print(f'{name}: verified cached file', flush=True)
            continue
        parts = destination / f'.{name}.parts'
        parts.mkdir(exist_ok=True)
        chunk_size = 4 * 1024 * 1024
        ranges = [(i, min(i + chunk_size, asset['bytes']))
                  for i in range(0, asset['bytes'], chunk_size)]
        base = (f"https://huggingface.co/{manifest['repository']}/resolve/"
                f"{manifest['revision']}/{asset['path']}")

        def part(bounds):
            start, end = bounds
            path = parts / str(start)
            if path.exists() and path.stat().st_size == end - start:
                return path
            # Unique range in URL prevents an intermediary reusing another range.
            request = urllib.request.Request(f'{base}?range_start={start}',
                headers={'Range': f'bytes={start}-{end-1}'})
            with urllib.request.urlopen(request, timeout=90) as response:
                content_range = response.headers.get('Content-Range', '')
                if not content_range.startswith(f'bytes {start}-{end-1}/'):
                    raise ValueError(f'Unexpected Content-Range: {content_range}')
                data = response.read(end - start + 1)
            if len(data) != end - start:
                raise ValueError('Incomplete model range')
            path.write_bytes(data)
            return path

        with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
            for done, _ in enumerate(pool.map(part, ranges), 1):
                if done % 10 == 0 or done == len(ranges):
                    print(f'{name}: {done}/{len(ranges)} ranges', flush=True)
        temporary = target.with_suffix(target.suffix + '.part')
        with temporary.open('wb') as output:
            for start, _ in ranges:
                path = parts / str(start)
                output.write(path.read_bytes())
                output.flush()
                # Bound assembly space to one range beyond the downloaded model.
                # If interrupted, missing ranges can be fetched again next run.
                path.unlink()
        if digest(temporary) != asset['sha256']:
            raise ValueError(f'{name}: SHA-256 mismatch; remove range parts and retry')
        temporary.replace(target)
        parts.rmdir()
        print(f'{name}: SHA-256 verified', flush=True)


def digest(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, default=Path('evaluation/nllb-model-manifest.json'))
    parser.add_argument('--destination', type=Path, default=Path('evaluation/private/nllb-ranged'))
    parser.add_argument('--workers', type=int, default=8)
    args = parser.parse_args()
    fetch(json.loads(args.manifest.read_text()), args.destination, args.workers)
