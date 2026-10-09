"""Score local JSONL: id, speaker, style, reference, raw, corrected.
No network or transcript logging. Results are corpus-level micro averages.
"""
import argparse
import json
import unicodedata


def normalize(text):
    text = unicodedata.normalize('NFC', text).casefold()
    return ' '.join(''.join(' ' if unicodedata.category(c).startswith('P') else c
                            for c in text).split())


def distance(a, b):
    row = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        nxt = [i]
        for j, y in enumerate(b, 1):
            nxt.append(min(nxt[-1] + 1, row[j] + 1, row[j - 1] + (x != y)))
        row = nxt
    return row[-1]


def score(rows):
    if not rows:
        raise ValueError('Dataset is empty')
    ids = [r['id'] for r in rows]
    if len(set(ids)) != len(ids):
        raise ValueError('Duplicate recording IDs')
    output = {'recordings': len(rows), 'speakers': len({r['speaker'] for r in rows}),
              'styles': sorted({r['style'] for r in rows})}
    refs = [normalize(r['reference']) for r in rows]
    for field in ('raw', 'corrected'):
        hyps = [normalize(r[field]) for r in rows]
        words = sum(len(r.split()) for r in refs)
        chars = sum(len(r.replace(' ', '')) for r in refs)
        output[field] = {
            'wer': sum(distance(r.split(), h.split()) for r, h in zip(refs, hyps)) / words if words else None,
            'cer': sum(distance(r.replace(' ', ''), h.replace(' ', '')) for r, h in zip(refs, hyps)) / chars if chars else None,
            'exact_match': sum(r == h for r, h in zip(refs, hyps)) / len(rows),
        }
    output['corrections_worsening_word_distance'] = sum(
        distance(normalize(r['reference']).split(), normalize(r['corrected']).split()) >
        distance(normalize(r['reference']).split(), normalize(r['raw']).split()) for r in rows)
    return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('jsonl')
    args = parser.parse_args()
    with open(args.jsonl, encoding='utf-8') as source:
        print(json.dumps(score([json.loads(line) for line in source if line.strip()]), indent=2))
