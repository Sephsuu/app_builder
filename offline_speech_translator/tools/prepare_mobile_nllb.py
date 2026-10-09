"""Generate small ONNX graphs referencing the original, SHA-verified weight files.

The vocabulary projection is evaluated in 8192-row slices, avoiding a 1 GiB
float32 vocabulary matrix. No weights or quantization parameters are changed.
The batch-one mobile decoder uses Gemm(transB=1) to consume contiguous rows
without a separate full-weight transpose on every token. --projection matmul
reproduces the old layout for regression comparisons.
Requires onnx; output graphs are packaged assets, original weights stay private.
Run with ConstantFolding disabled so the slices are materialized one at a time.
"""
import argparse
import hashlib
import json
from pathlib import Path

import onnx
from onnx import helper, TensorProto


def varint(stream):
    value = 0
    for shift in range(0, 70, 7):
        byte = stream.read(1)
        if not byte:
            raise ValueError('Truncated protobuf')
        value |= (byte[0] & 127) << shift
        if byte[0] < 128:
            return value
    raise ValueError('Invalid protobuf varint')


def fields(stream, end):
    while stream.tell() < end:
        tag = varint(stream)
        wire = tag & 7
        if wire == 2:
            size = varint(stream)
        elif wire == 0:
            start = stream.tell()
            varint(stream)
            size = stream.tell() - start
            stream.seek(start)
        elif wire in (1, 5):
            size = 8 if wire == 1 else 4
        else:
            raise ValueError('Unsupported protobuf wire type')
        start = stream.tell()
        assert start + size <= end
        yield tag >> 3, wire, start, size
        stream.seek(start + size)


def weight_offsets(path):
    result = {}
    with path.open('rb') as stream:
        for field, wire, start, size in fields(stream, path.stat().st_size):
            if field != 7 or wire != 2:  # ModelProto.graph
                continue
            for gf, gw, gs, gz in fields(stream, start + size):
                if gf != 5 or gw != 2:  # GraphProto.initializer
                    continue
                name = None
                raw = None
                for tf, tw, ts, tz in fields(stream, gs + gz):
                    if tf == 8 and tw == 2:
                        name = stream.read(tz).decode('utf-8')
                    elif tf == 9 and tw == 2:
                        raw = (ts, tz)
                if raw:
                    assert name
                    result[name] = raw
    return result


def sliced_projection(graph, projection_layout='gemm'):
    replaced = 0
    for node in graph.node:
        for attribute in node.attribute:
            if attribute.type == onnx.AttributeProto.GRAPH:
                replaced += sliced_projection(attribute.g, projection_layout)
    nodes = list(graph.node)
    projections = [n for n in nodes if n.op_type == 'MatMul' and n.name == '/lm_head/MatMul']
    for projection in projections:
        dq = next(n for n in nodes if projection.input[1] in n.output)
        transpose = next(n for n in nodes if dq.input[0] in n.output)
        assert dq.op_type == 'DequantizeLinear' and transpose.op_type == 'Transpose'
        assert not transpose.attribute or list(transpose.attribute[0].ints) == [1, 0]
        assert sum(projection.input[1] in n.input for n in nodes) == 1
        assert sum(dq.input[0] in n.input for n in nodes) == 1
        weight = transpose.input[0]
        assert weight == 'model.shared.weight_merged_0_quantized'
        chunks = []
        replacement = []
        hidden = projection.input[0]
        if projection_layout == 'gemm':
            # Gemm transB reads the contiguous vocabulary rows directly. Avoid
            # transposing ~1 GiB of dequantized weights on every generated token.
            graph.initializer.extend([
                helper.make_tensor('sulti_hidden_shape', TensorProto.INT64, [2], [-1, 1024]),
                helper.make_tensor('sulti_logits_shape', TensorProto.INT64, [3], [1, -1, 256206]),
            ])
            replacement.append(helper.make_node('Reshape', [hidden, 'sulti_hidden_shape'], ['sulti_hidden_2d']))
            hidden = 'sulti_hidden_2d'
        for start in range(0, 256206, 8192):
            prefix = f'sulti_vocab_{start}'
            for suffix, value in [('start', start), ('end', min(start + 8192, 256206)), ('axis', 0)]:
                graph.initializer.append(helper.make_tensor(prefix + '_' + suffix, TensorProto.INT64, [1], [value]))
            slice_start = prefix + '_start'
            if chunks:
                # A data dependency keeps ORT from materializing every slice's
                # float weights before any MatMul consumes them. Greater(x,x)
                # is false even for NaN/Inf; the cast therefore always adds 0.
                replacement.extend([
                    helper.make_node('ReduceSum', [chunks[-1]], [prefix + '_sum'], keepdims=0),
                    helper.make_node('Greater', [prefix + '_sum', prefix + '_sum'], [prefix + '_false']),
                    helper.make_node('Cast', [prefix + '_false'], [prefix + '_zero'], to=TensorProto.INT64),
                    helper.make_node('Add', [slice_start, prefix + '_zero'], [prefix + '_ordered_start']),
                ])
                slice_start = prefix + '_ordered_start'
            replacement.extend([
                helper.make_node('Slice', [weight, slice_start, prefix + '_end', prefix + '_axis'], [prefix + '_q']),
                helper.make_node('DequantizeLinear', [prefix + '_q', *dq.input[1:]], [prefix + '_float']),
            ])
            if projection_layout == 'gemm':
                replacement.append(helper.make_node('Gemm', [hidden, prefix + '_float'], [prefix + '_logits'], transB=1))
            else:
                replacement.extend([
                    helper.make_node('Transpose', [prefix + '_float'], [prefix + '_weight'], perm=[1, 0]),
                    helper.make_node('MatMul', [hidden, prefix + '_weight'], [prefix + '_logits']),
                ])
            chunks.append(prefix + '_logits')
        if projection_layout == 'gemm':
            replacement.extend([
                helper.make_node('Concat', chunks, ['sulti_logits_2d'], axis=-1),
                helper.make_node('Reshape', ['sulti_logits_2d', 'sulti_logits_shape'], list(projection.output)),
            ])
        else:
            replacement.append(helper.make_node('Concat', chunks, list(projection.output), axis=-1))
        revised = []
        for node in nodes:
            if node is dq or node is transpose:
                continue
            if node is projection:
                revised.extend(replacement)
            else:
                revised.append(node)
        nodes = revised
        replaced += 1
    del graph.node[:]
    graph.node.extend(nodes)
    return replaced


def prepare(directory, output, manifest, projection_layout='gemm'):
    output.mkdir(parents=True, exist_ok=True)
    report = {'source_revision': manifest['revision'], 'projection_rows': 8192,
              'projection_layout': projection_layout, 'files': []}
    for asset in manifest['files']:
        if not asset['path'].endswith('.onnx'):
            continue
        source = directory / Path(asset['path']).name
        with source.open('rb') as stream:
            assert hashlib.file_digest(stream, 'sha256').hexdigest() == asset['sha256']
        offsets = weight_offsets(source)
        model = onnx.load(source)
        if 'decoder' in source.name:
            weight = next(t for t in model.graph.initializer
                          if t.name == 'model.shared.weight_merged_0_quantized')
            assert list(weight.dims) == [256206, 1024], 'Unexpected pinned decoder dimensions'
        for tensor in model.graph.initializer:
            if tensor.name not in offsets:
                continue
            offset, size = offsets[tensor.name]
            assert size == len(tensor.raw_data)
            tensor.ClearField('raw_data')
            tensor.data_location = TensorProto.EXTERNAL
            for key, value in [('location', source.name), ('offset', str(offset)), ('length', str(size))]:
                entry = tensor.external_data.add()
                entry.key, entry.value = key, value
        count = sliced_projection(model.graph, projection_layout)
        assert count == (2 if 'decoder' in source.name else 0)
        name = 'decoder_mobile.onnx' if count else 'encoder_mobile.onnx'
        target = output / name
        target.write_bytes(model.SerializeToString())
        report['files'].append({'name': name, 'bytes': target.stat().st_size,
                                'sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
                                'sliced_projections': count})
        print(report['files'][-1], flush=True)
        del model
    (output / 'manifest.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('models', type=Path)
    parser.add_argument('--output', type=Path, default=Path('android/app/src/main/assets/nllb-mobile'))
    parser.add_argument('--projection', choices=['matmul', 'gemm'], default='gemm')
    args = parser.parse_args()
    prepare(args.models, args.output, json.loads(Path('evaluation/nllb-model-manifest.json').read_text()), args.projection)
