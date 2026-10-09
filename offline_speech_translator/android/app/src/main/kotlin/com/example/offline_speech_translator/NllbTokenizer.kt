package com.example.offline_speech_translator

/** The pinned tokenizer has 256,000 SentencePiece entries and fairseq offset 1. */
class NllbTokenizer(path: String) : AutoCloseable {
    companion object {
        init { System.loadLibrary("sulti_tokenizer") }
    }
    private var handle = load(path)
    private external fun load(path: String): Long
    private external fun encodeNative(handle: Long, text: ByteArray): IntArray
    private external fun decodeNative(handle: Long, ids: IntArray): ByteArray
    private external fun release(handle: Long)

    fun encode(text: String, source: String): LongArray {
        check(handle != 0L)
        val pieces = encodeNative(handle, text.toByteArray(Charsets.UTF_8))
        return NllbTokens.encoder(pieces, source)
    }
    fun decode(tokens: List<Long>): String {
        check(handle != 0L)
        val pieces = tokens.filter { it in 3L..256000L }
            .map { if (it == 3L) 0 else (it - 1).toInt() }.toIntArray()
        return String(decodeNative(handle, pieces), Charsets.UTF_8).trim()
    }
    override fun close() {
        if (handle != 0L) release(handle)
        handle = 0
    }
}

object NllbTokens {
    // Verified against tokenizer.json at 261c31d1a5732c67cdd16d80e8d6088507c7ccea.
    val languages = mapOf("tgl_Latn" to 256174L, "ceb_Latn" to 256035L)
    fun language(code: String): Long = requireNotNull(languages[code]) {
        "Unsupported translation language: $code"
    }
    fun encoder(pieces: IntArray, source: String): LongArray =
        longArrayOf(language(source)) +
            pieces.map { if (it == 0) 3L else it.toLong() + 1 }.toLongArray() +
            longArrayOf(2)
    fun decoderPrefix(target: String) = longArrayOf(2, language(target))
}
