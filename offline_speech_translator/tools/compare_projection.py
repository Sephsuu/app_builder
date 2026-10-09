"""Compare sliced MatMul and Gemm NLLB graphs with actual offline inference.

Generate each graph directory using prepare_mobile_nllb.py --projection
matmul|gemm, then put (or symlink) the original verified ONNX weight files and
sentencepiece.bpe.model in each directory. No model downloads are performed.
"""
import argparse
import hashlib
import json
import statistics
import time
from pathlib import Path

import onnxruntime as ort
import sentencepiece as spm
from evaluate_nllb import translate


def verify(directory, manifest):
    for asset in manifest['files']:
        with (directory / Path(asset['path']).name).open('rb') as stream:
            if hashlib.file_digest(stream, 'sha256').hexdigest() != asset['sha256']:
                raise ValueError('Model checksum mismatch')
    metadata = json.loads((directory / 'manifest.json').read_text())
    for graph in metadata['files']:
        with (directory / graph['name']).open('rb') as stream:
            if hashlib.file_digest(stream, 'sha256').hexdigest() != graph['sha256']:
                raise ValueError('Graph checksum mismatch')
    return metadata


def compare(baseline, candidate, output):
    manifest = json.loads(Path('evaluation/nllb-model-manifest.json').read_text())
    graphs = {label: verify(directory, manifest)
              for label, directory in [('baseline', baseline), ('candidate', candidate)]}
    tokenizer = spm.SentencePieceProcessor(model_file=str(baseline / 'sentencepiece.bpe.model'))
    cases = [{'id': 'user-prepared', 'text': 'Saan tayo pupunta mamaya', 'source': 'tgl_Latn'}]
    cases += json.loads(Path('evaluation/translation-cases.json').read_text())['cases']
    report = {'scope': 'Host CPU output regression and exploratory latency, not phone speed or human quality acceptance',
              'revision': manifest['revision'], 'runtime': ort.__version__,
              'graphs': graphs, 'complete': False, 'results': []}
    for case in cases:
        row = {key: case[key] for key in ['id', 'text', 'source']}
        target = 'ceb_Latn' if case['source'] == 'tgl_Latn' else 'tgl_Latn'
        for label, directory in [('baseline', baseline), ('candidate', candidate)]:
            start = time.perf_counter()
            row[label] = translate(directory, tokenizer, case['text'], case['source'], target, True)
            row[label + '_seconds'] = time.perf_counter() - start
        row['identical'] = row['baseline'] == row['candidate']
        report['results'].append(row)
        output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
        print(json.dumps(row, ensure_ascii=False), flush=True)
    report['complete'] = True
    report['summary'] = {
        'cases': len(cases),
        'changed_outputs': [row['id'] for row in report['results'] if not row['identical']],
        **{label + '_median_seconds': statistics.median(row[label + '_seconds'] for row in report['results'])
           for label in ['baseline', 'candidate']},
    }
    output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('benchmarks/translation-gemm-host.json'))
    args = parser.parse_args()
    compare(args.baseline, args.candidate, args.output)
