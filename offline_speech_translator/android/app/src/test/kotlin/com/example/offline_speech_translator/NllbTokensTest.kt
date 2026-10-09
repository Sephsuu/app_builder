package com.example.offline_speech_translator

import org.junit.Assert.*
import org.junit.Test

class NllbTokensTest {
    @Test fun sourcePrefixAndUnknownTokenFollowOriginalTokenizer() {
        // Real SentencePiece IDs, fairseq offset and unk remap are not identical.
        assertArrayEquals(longArrayOf(256174, 4, 3, 41, 2),
            NllbTokens.encoder(intArrayOf(3, 0, 40), "tgl_Latn"))
        assertArrayEquals(longArrayOf(256035, 4, 3, 41, 2),
            NllbTokens.encoder(intArrayOf(3, 0, 40), "ceb_Latn"))
    }
    @Test fun forcedTargetComesAfterDecoderStart() {
        assertArrayEquals(longArrayOf(2, 256035), NllbTokens.decoderPrefix("ceb_Latn"))
        assertArrayEquals(longArrayOf(2, 256174), NllbTokens.decoderPrefix("tgl_Latn"))
    }
    @Test(expected = IllegalArgumentException::class)
    fun rejectsWhisperCodeInsteadOfSilentlyUsingItForNllb() {
        NllbTokens.encoder(intArrayOf(3), "tl")
    }
}
