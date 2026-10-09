import unittest
from score_asr import distance, normalize, score

class ScoringTests(unittest.TestCase):
    def test_edit_distance(self):
        self.assertEqual(distance('abc', 'adc'), 1)
        self.assertEqual(distance([], ['insert']), 1)
        self.assertEqual(distance(['delete'], []), 1)
    def test_normalization(self):
        self.assertEqual(normalize('  Kumain,  ANA! '), 'kumain ana')
    def test_false_correction(self):
        result = score([dict(id='1', speaker='a', style='quiet', reference='kumain na', raw='kumain na', corrected='kakain na')])
        self.assertEqual(result['raw']['wer'], 0)
        self.assertEqual(result['corrected']['wer'], .5)
        self.assertEqual(result['corrections_worsening_word_distance'], 1)
    def test_empty_rejected(self):
        with self.assertRaises(ValueError):
            score([])

if __name__ == '__main__':
    unittest.main()
