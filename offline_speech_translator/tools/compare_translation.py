"""Compare full-passage NLLB with independent-line inference on local weights.

Uses the existing evaluation venv; no downloads or new runtime dependencies.
References are draft review material, not evidence of human-reviewed quality.
Only literal name retention is counted; it is not a semantic accuracy metric.
"""
import argparse
import hashlib
import json
import platform
import statistics
import time
from pathlib import Path

import onnxruntime as ort
import sentencepiece as spm
from evaluate_nllb import CODES, translate


def compare(models, cases, manifest, output):
    for item in manifest['files']:
        with (models / Path(item['path']).name).open('rb') as stream:
            if hashlib.file_digest(stream, 'sha256').hexdigest() != item['sha256']:
                raise ValueError('Model checksum mismatch')
    graphs = json.loads(Path('android/app/src/main/assets/nllb-mobile/manifest.json').read_text())
    for item in graphs['files']:
        with (models / item['name']).open('rb') as stream:
            if hashlib.file_digest(stream, 'sha256').hexdigest() != item['sha256']:
                raise ValueError('Mobile graph checksum mismatch')
    tokenizer = spm.SentencePieceProcessor(model_file=str(models / 'sentencepiece.bpe.model'))
    report = dict(scope='Real host CPU inference; not Android latency or human quality acceptance',
                  host=platform.platform(), runtime=ort.__version__, revision=manifest['revision'],
                  references='AI-drafted, pending independent fluent-speaker review', results=[])
    for case in cases:
        target = next(code for code in CODES if code != case['source'])
        start = time.perf_counter()
        baseline = translate(models, tokenizer, case['text'], case['source'], target, True)
        baseline_seconds = time.perf_counter() - start
        lines = [line.strip() for line in case['text'].splitlines() if line.strip()]
        if len(lines) > 1:
            start = time.perf_counter()
            candidate = '\n'.join(translate(models, tokenizer, line, case['source'], target, True)
                                  for line in lines)
            candidate_seconds = time.perf_counter() - start
        else:
            candidate, candidate_seconds = baseline, None  # Exactly the same inference path.
        row = dict(case, target=target, baseline=baseline, candidate=candidate,
                   baseline_seconds=baseline_seconds, candidate_seconds=candidate_seconds,
                   missing_names_baseline=[n for n in case['required_names'] if n not in baseline],
                   missing_names_candidate=[n for n in case['required_names'] if n not in candidate])
        report['results'].append(row)
        output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
        print(json.dumps(row, ensure_ascii=False), flush=True)
    report['summary'] = dict(cases=len(cases),
        missing_names_baseline=sum(len(r['missing_names_baseline']) for r in report['results']),
        missing_names_candidate=sum(len(r['missing_names_candidate']) for r in report['results']),
        median_baseline_seconds=statistics.median(r['baseline_seconds'] for r in report['results']))
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--models', type=Path, default=Path('evaluation/private/nllb-ranged'))
    parser.add_argument('--cases', type=Path, default=Path('evaluation/translation-cases.json'))
    parser.add_argument('--output', type=Path, default=Path('benchmarks/translation-refinement-comparison.json'))
    args = parser.parse_args()
    compare(args.models, json.loads(args.cases.read_text())['cases'],
            json.loads(Path('evaluation/nllb-model-manifest.json').read_text()), args.output)
