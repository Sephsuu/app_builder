package com.example.offline_speech_translator

import ai.onnxruntime.*
import java.nio.FloatBuffer
import java.nio.LongBuffer

/** CPU int8 inference. All calls and disposal are serialized by OfflineTranslation. */
class NllbTranslator(private val models: TranslationModels) {
    private val environment = OrtEnvironment.getEnvironment()

    private fun session(name: String, checkCancelled: () -> Unit): OrtSession = OrtSession.SessionOptions().use { options ->
        options.setIntraOpNumThreads(4)
        options.setInterOpNumThreads(1)
        options.setOptimizationLevel(OrtSession.SessionOptions.OptLevel.BASIC_OPT)
        options.setCPUArenaAllocator(false)
        options.setMemoryPatternOptimization(false)
        // Folding the vocabulary slices would recreate the 1 GiB float matrix.
        options.addConfigEntry("optimization.disable_specified_optimizers", "ConstantFolding")
        environment.createSession(models.mobileGraph(name, checkCancelled).absolutePath, options)
    }

    fun translate(text: String, source: String, target: String,
                  run: OrtSession.RunOptions, checkCancelled: () -> Unit): String {
        require(source != target) { "Choose different source and target languages." }
        NllbTokens.language(source)
        NllbTokens.language(target)
        require(text.isNotBlank() && text.length <= 8000) { "Enter a shorter, nonempty passage." }
        check(models.installed(checkCancelled)) { "Install the translation model first." }
        NllbTokenizer(models.file("sentencepiece.bpe.model").absolutePath).use { tokenizer ->
            val ids = tokenizer.encode(text, source)
            require(ids.size <= 512) { "This passage exceeds 512 tokens. Edit it into shorter passages; no text was truncated." }
            checkCancelled()
            longTensor(ids).use { input ->
                longTensor(LongArray(ids.size) { 1 }).use { mask ->
                    // Materialize only the small encoder state, then release its
                    // session before allocating the larger decoder session.
                    val hidden = session("encoder_mobile.onnx", checkCancelled).use { encoder ->
                        encoder.run(mapOf("input_ids" to input, "attention_mask" to mask), run).use { result ->
                            val tensor = result.get("last_hidden_state").get() as OnnxTensor
                            val data = tensor.floatBuffer
                            val copy = FloatArray(data.remaining())
                            data.get(copy)
                            OnnxTensor.createTensor(environment, FloatBuffer.wrap(copy), tensor.info.shape)
                        }
                    }
                    hidden.use {
                        checkCancelled()
                        session("decoder_mobile.onnx", checkCancelled).use { decoder ->
                            return decode(decoder, hidden, mask, tokenizer, target, run, checkCancelled)
                        }
                    }
                }
            }
        }
    }

    private fun decode(decoder: OrtSession, hidden: OnnxTensor, mask: OnnxTensor,
                       tokenizer: NllbTokenizer, target: String,
                       run: OrtSession.RunOptions, checkCancelled: () -> Unit): String {
        val empty = OnnxTensor.createTensor(environment, FloatBuffer.allocate(0), longArrayOf(1, 16, 0, 64))
        val noCache = OnnxTensor.createTensor(environment, booleanArrayOf(false))
        val useCache = OnnxTensor.createTensor(environment, booleanArrayOf(true))
        var first: OrtSession.Result? = null
        var previous: OrtSession.Result? = null
        var nextIds = NllbTokens.decoderPrefix(target)
        val generated = mutableListOf<Long>()
        try {
            repeat(512) {
                checkCancelled()
                val cached = first != null
                longTensor(nextIds).use { tokens ->
                    val feeds = mutableMapOf<String, OnnxTensor>(
                        "input_ids" to tokens,
                        "encoder_attention_mask" to mask,
                        "encoder_hidden_states" to hidden,
                        "use_cache_branch" to if (cached) useCache else noCache
                    )
                    for (layer in 0 until 12) {
                        for (kind in listOf("decoder", "encoder")) {
                            for (kv in listOf("key", "value")) {
                                val value = if (!cached) empty else {
                                    val owner = if (kind == "encoder") first!! else previous!!
                                    owner.get("present.$layer.$kind.$kv").get() as OnnxTensor
                                }
                                feeds["past_key_values.$layer.$kind.$kv"] = value
                            }
                        }
                    }
                    val result = decoder.run(feeds, run)
                    val old = previous
                    if (first == null) first = result
                    previous = result
                    if (old != null && old !== first) old.close()
                    val logits = result.get("logits").get() as OnnxTensor
                    val scores = logits.floatBuffer
                    val vocabulary = logits.info.shape.last().toInt()
                    check(vocabulary == 256206) { "Unexpected NLLB vocabulary." }
                    val offset = scores.limit() - vocabulary
                    var best = 0
                    var maximum = Float.NEGATIVE_INFINITY
                    for (index in 0 until vocabulary) {
                        val score = scores.get(offset + index)
                        if (score > maximum) { maximum = score; best = index }
                    }
                    check(maximum.isFinite()) { "Translation produced invalid scores." }
                    if (best == 2) {
                        val translated = tokenizer.decode(generated)
                        check(translated.isNotBlank()) { "No translation generated. Edit the source and retry." }
                        return translated
                    }
                    check(best in 3..256000) { "Translation produced an unexpected control token. Retry." }
                    generated.add(best.toLong())
                    nextIds = longArrayOf(best.toLong())
                }
            }
            error("Translation exceeded its output limit. Shorten the source and retry; partial text was not accepted.")
        } finally {
            if (previous !== first) previous?.close()
            first?.close()
            empty.close()
            noCache.close()
            useCache.close()
        }
    }

    private fun longTensor(ids: LongArray) = OnnxTensor.createTensor(
        environment, LongBuffer.wrap(ids), longArrayOf(1, ids.size.toLong()))
}
