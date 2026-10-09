"""Convert the pinned Cebuano Safetensors checkpoint to Whisper GGML F16.

Uses the tensor-name mapping of whisper.cpp's MIT-licensed convert-h5-to-ggml.py
(v1.8.2), reading Safetensors directly instead of executing a PyTorch pickle.
Reuses and verifies the stock multilingual Tiny model's mel filters/token bytes.
Run the official whisper.cpp quantize executable on the output with Q5_1.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct

import numpy as np
from safetensors import safe_open

SOURCE_SHA = '6c2bc3696905b5fbddce5687b7bcfec15d841d8b6530a9602a2e90d8249559d7'
TINY_SHA = '818710568da3ca15689e31a743197b520007872ff9576237bda97bd1b469c3d7'
LAYER_NAMES = {
    'self_attn.k_proj': 'attn.key', 'self_attn.q_proj': 'attn.query',
    'self_attn.v_proj': 'attn.value', 'self_attn.out_proj': 'attn.out',
    'self_attn_layer_norm': 'attn_ln', 'encoder_attn.k_proj': 'cross_attn.key',
    'encoder_attn.q_proj': 'cross_attn.query', 'encoder_attn.v_proj': 'cross_attn.value',
    'encoder_attn.out_proj': 'cross_attn.out', 'encoder_attn_layer_norm': 'cross_attn_ln',
    'fc1': 'mlp.0', 'fc2': 'mlp.2', 'final_layer_norm': 'mlp_ln',
}
OTHER_NAMES = {
    'encoder.layer_norm': 'encoder.ln_post', 'decoder.layer_norm': 'decoder.ln',
    'encoder.embed_positions.weight': 'encoder.positional_embedding',
    'decoder.embed_positions.weight': 'decoder.positional_embedding',
    'decoder.embed_tokens.weight': 'decoder.token_embedding.weight',
}


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def byte_decoder():
    values = list(range(33, 127)) + list(range(161, 173)) + list(range(174, 256))
    characters = values[:]
    extra = 0
    for value in range(256):
        if value not in values:
            values.append(value)
            characters.append(256 + extra)
            extra += 1
    return {chr(char): value for char, value in zip(characters, values)}


def frontend(tiny, tokenizer):
    assert digest(tiny) == TINY_SHA
    decoder = byte_decoder()
    by_id = {value: key for key, value in tokenizer['model']['vocab'].items()}
    with tiny.open('rb') as stream:
        header = struct.unpack('<12i', stream.read(48))
        assert header[0] == 0x67676D6C and header[1] == 51865 and header[10] == 80
        start = stream.tell()
        mels, bins = struct.unpack('<2i', stream.read(8))
        assert (mels, bins) == (80, 201)
        stream.seek(mels * bins * 4, 1)
        count = struct.unpack('<i', stream.read(4))[0]
        assert count == 50257
        for token in range(count):
            size = struct.unpack('<i', stream.read(4))[0]
            actual = stream.read(size)
            expected = bytes(decoder[c] for c in by_id[token])
            assert actual == expected, f'Tokenizer differs at {token}'
        end = stream.tell()
        stream.seek(start)
        return stream.read(end - start)


def tensor_name(source):
    assert source.startswith('model.')
    parts = source.split('.')[1:]
    if len(parts) > 3 and parts[1] == 'layers':
        parts[1] = 'blocks'
        return '.'.join(parts[:3] + [LAYER_NAMES['.'.join(parts[3:-1])], parts[-1]])
    name = '.'.join(parts)
    if name in OTHER_NAMES:
        return OTHER_NAMES[name]
    for source_prefix, target_prefix in OTHER_NAMES.items():
        if name.startswith(source_prefix + '.'):
            return target_prefix + name[len(source_prefix):]
    assert name.startswith(('encoder.conv1.', 'encoder.conv2.')), name
    return name


def convert(directory, tiny, output):
    source = directory / 'model.safetensors'
    assert digest(source) == SOURCE_SHA
    config = json.loads((directory / 'config.json').read_text())
    assert config['d_model'] == 768 and config['num_mel_bins'] == 80
    assert config['vocab_size'] == 51865 and config['max_target_positions'] == 448
    tokenizer = json.loads((directory / 'tokenizer.json').read_text())
    tokens = {token['content']: token['id'] for token in tokenizer['added_tokens']}
    assert tokens['<|tl|>'] == 50348 and tokens['<|transcribe|>'] == 50359
    front = frontend(tiny, tokenizer)
    header = [0x67676D6C, 51865, 1500, 768, 12, 12, 448, 768, 12, 12, 80, 1]
    count = 0
    with safe_open(source, framework='np') as weights, output.open('wb') as target:
        target.write(struct.pack('<12i', *header))
        target.write(front)
        for source_name in weights.keys():
            if source_name == 'proj_out.weight':
                # Tied to decoder.token_embedding.weight in Whisper.
                assert config['tie_word_embeddings']
                continue
            name = tensor_name(source_name)
            data = weights.get_tensor(source_name).squeeze()
            if name in ['encoder.conv1.bias', 'encoder.conv2.bias']:
                data = data.reshape(data.shape[0], 1)
            full_precision = (data.ndim < 2 or name in [
                'encoder.conv1.bias', 'encoder.conv2.bias',
                'encoder.positional_embedding', 'decoder.positional_embedding'])
            data = data.astype('<f4' if full_precision else '<f2')
            encoded = name.encode('utf-8')
            target.write(struct.pack('<3i', data.ndim, len(encoded), 0 if full_precision else 1))
            target.write(struct.pack('<' + 'i' * data.ndim, *reversed(data.shape)))
            target.write(encoded)
            data.tofile(target)
            count += 1
    print(json.dumps({'output': str(output), 'bytes': output.stat().st_size,
                      'sha256': digest(output), 'tensors': count, 'vocabulary_parity': 50257}, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('checkpoint', type=Path)
    parser.add_argument('--tiny', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    convert(args.checkpoint, args.tiny, args.output)
