"""Real local NLLB smoke evaluation, matching Android's greedy cached decoder.

Requires onnxruntime==1.23.2, sentencepiece==0.2.0, numpy, tokenizers.
No network access. Outputs model text and measured host latency; this is not a
human translation-quality score or an Android performance benchmark.
"""
import argparse
import gc
import hashlib
import json
from pathlib import Path
import resource
import time

import numpy as np
import onnxruntime as ort
import sentencepiece as spm
from tokenizers import Tokenizer

CODES = {'tgl_Latn': 256174, 'ceb_Latn': 256035}
CASES = [
    ('tgl_Latn', 'Kumusta ka?'),
    ('ceb_Latn', 'Kumusta ka?'),
    ('tgl_Latn', 'Nasaan si Maria?'),
    ('ceb_Latn', 'Asa si Maria?'),
    ('tgl_Latn', 'Hindi ako pupunta sa Mayo 12.'),
    ('ceb_Latn', 'Dili ko gusto og kape.'),
    ('tgl_Latn', 'Pakibigay kay Juan ang 3 libro bukas.'),
    ('ceb_Latn', 'Palihog ihatag kang Juan ang 3 ka libro ugma.'),
    ('tgl_Latn', 'I-send ang report sa alas 3. Huwag kalimutan ang pangalan ni Ana.'),
    ('ceb_Latn', 'I-send ang report alas 3. Ayaw kalimti ang ngalan ni Ana.'),
]


def session(path, mobile=False):
    options = ort.SessionOptions()
    options.intra_op_num_threads = 4
    options.inter_op_num_threads = 1
    options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_BASIC
    options.enable_cpu_mem_arena = False
    options.enable_mem_pattern = False
    if mobile:
        options.add_session_config_entry('optimization.disable_specified_optimizers', 'ConstantFolding')
    return ort.InferenceSession(str(path), options, providers=['CPUExecutionProvider'])


def translate(directory, tokenizer, text, source, target, mobile=False):
    pieces = tokenizer.encode(text)
    ids = np.array([[CODES[source]] + [i + 1 if i else 3 for i in pieces] + [2]], dtype=np.int64)
    if ids.size > 512:
        raise ValueError('Input exceeds 512 tokens')
    mask = np.ones_like(ids)
    encoder = session(directory / ('encoder_mobile.onnx' if mobile else 'encoder_model_quantized.onnx'), mobile)
    hidden = encoder.run(['last_hidden_state'], {'input_ids': ids, 'attention_mask': mask})[0]
    del encoder
    gc.collect()
    decoder = session(directory / ('decoder_mobile.onnx' if mobile else 'decoder_model_merged_quantized.onnx'), mobile)
    names = [output.name for output in decoder.get_outputs()]
    feeds = {'encoder_hidden_states': hidden, 'encoder_attention_mask': mask,
             'input_ids': np.array([[2, CODES[target]]], dtype=np.int64),
             'use_cache_branch': np.array([False])}
    for layer in range(12):
        for kind in ('encoder', 'decoder'):
            for kv in ('key', 'value'):
                feeds[f'past_key_values.{layer}.{kind}.{kv}'] = np.zeros((1, 16, 0, 64), dtype=np.float32)
    generated = []
    first = None
    for _ in range(512):
        result = dict(zip(names, decoder.run(None, feeds)))
        if first is None:
            first = result
        token = int(np.argmax(result['logits'][0, -1]))
        if token == 2:
            return tokenizer.decode([0 if t == 3 else t - 1 for t in generated])
        if not 3 <= token <= 256000:
            raise ValueError(f'Unexpected model control token {token}')
        generated.append(token)
        feeds['input_ids'] = np.array([[token]], dtype=np.int64)
        feeds['use_cache_branch'] = np.array([True])
        for layer in range(12):
            for kind in ('encoder', 'decoder'):
                for kv in ('key', 'value'):
                    owner = first if kind == 'encoder' else result
                    feeds[f'past_key_values.{layer}.{kind}.{kv}'] = owner[f'present.{layer}.{kind}.{kv}']
    raise ValueError('Output limit reached; partial translation rejected')


def evaluate(directory, fast_path, manifest, mobile=False):
    for asset in manifest['files']:
        path = directory / Path(asset['path']).name
        with path.open('rb') as source:
            actual = hashlib.file_digest(source, 'sha256').hexdigest()
        if actual != asset['sha256']:
            raise ValueError(f'Unverified model: {path.name}')
    tokenizer = spm.SentencePieceProcessor(model_file=str(directory / 'sentencepiece.bpe.model'))
    fast = Tokenizer.from_file(str(fast_path))
    for code, token_id in CODES.items():
        assert fast.token_to_id(code) == token_id
    tokenizer_cases = [text for _, text in CASES] + ['Café — １２３. Jose\u0301', '  Cebuano   text\nwith pauses.']
    for text in tokenizer_cases:
        actual = [i + 1 if i else 3 for i in tokenizer.encode(text)]
        assert actual == fast.encode(text, add_special_tokens=False).ids, f'Tokenizer mismatch: {text}'
    report = {'revision': manifest['revision'], 'runtime': ort.__version__,
              'scope': 'Host CPU inference, not native-speaker quality or phone performance',
              'mobile_graph': mobile,
              'tokenizer_parity_cases': len(tokenizer_cases), 'results': []}
    for source, text in CASES:
        target = next(code for code in CODES if code != source)
        start = time.perf_counter()
        output = translate(directory, tokenizer, text, source, target, mobile)
        row = {'source': source, 'target': target, 'input': text, 'output': output,
               'seconds': time.perf_counter() - start}
        print(json.dumps(row, ensure_ascii=False), flush=True)
        report['results'].append(row)
    report['host_maxrss_raw'] = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('models', type=Path)
    parser.add_argument('--tokenizer-json', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, default=Path('evaluation/nllb-model-manifest.json'))
    parser.add_argument('--output', type=Path, default=Path('evaluation/private/nllb-results.json'))
    parser.add_argument('--mobile', action='store_true')
    args = parser.parse_args()
    report = evaluate(args.models, args.tokenizer_json, json.loads(args.manifest.read_text()), args.mobile)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
