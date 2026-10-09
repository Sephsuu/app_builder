package com.example.offline_speech_translator

import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Installed local voices only; no substitute language or cloud synthesis. */
class OfflineVoice(context: Context, messenger: BinaryMessenger) : AutoCloseable {
    private val main = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "sulti/offline_voice")
    private var engine: TextToSpeech? = null
    private var ready = false
    private var initializationFailed = false
    private var closed = false
    private val waiting = mutableListOf<() -> Unit>()
    private val initializationTimeout = Runnable {
        if (!ready && !closed) {
            initializationFailed = true
            val callbacks = waiting.toList()
            waiting.clear()
            callbacks.forEach { it() }
        }
    }
    private var utterance = 0L
    private var speaking: Pair<String, MethodChannel.Result>? = null

    init {
        main.postDelayed(initializationTimeout, 10_000)
        engine = TextToSpeech(context) { status -> main.post {
            if (!closed) {
                main.removeCallbacks(initializationTimeout)
                ready = status == TextToSpeech.SUCCESS
                initializationFailed = !ready
                engine?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(id: String?) {}
                    override fun onDone(id: String?) { complete(id, null) }
                    @Deprecated("Android callback")
                    override fun onError(id: String?) { complete(id, "Speech synthesis failed.") }
                    override fun onError(id: String?, code: Int) { complete(id, "Speech synthesis failed ($code).") }
                    override fun onStop(id: String?, interrupted: Boolean) { complete(id, null) }
                })
                val callbacks = waiting.toList()
                waiting.clear()
                callbacks.forEach { it() }
            }
        } }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "stop" -> { stop(); result.success(null) }
                "supports", "speak" -> whenReady {
                    if (!ready || closed) {
                        if (call.method == "supports") result.success(false)
                        else result.error("voice", "No offline speech engine is available.", null)
                    } else {
                        val language = if (call.method == "supports") call.arguments as? String
                                       else call.argument<String>("language")
                        val voice = selectVoice(language)
                        if (call.method == "supports") result.success(voice != null)
                        else {
                            val text = call.argument<String>("text") ?: ""
                            if (voice == null) result.error("voice", "No installed offline voice for $language.", null)
                            else if (text.isBlank() || text.length > TextToSpeech.getMaxSpeechInputLength()) {
                                result.error("voice", "This text is empty or too long for the installed voice.", null)
                            } else {
                                stop()
                                val tts = engine!!
                                if (tts.setVoice(voice) != TextToSpeech.SUCCESS) {
                                    result.error("voice", "The selected offline voice could not be loaded.", null)
                                } else {
                                    val id = (++utterance).toString()
                                    speaking = id to result
                                    val parameters = Bundle().apply {
                                        putString(TextToSpeech.Engine.KEY_FEATURE_EMBEDDED_SYNTHESIS, "true")
                                    }
                                    if (tts.speak(text, TextToSpeech.QUEUE_FLUSH, parameters, id) == TextToSpeech.ERROR) {
                                        complete(id, "The offline voice could not start.")
                                    }
                                }
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    private fun whenReady(action: () -> Unit) {
        if (ready || initializationFailed || closed) action() else waiting.add(action)
    }
    private fun selectVoice(language: String?): Voice? {
        val codes = when (language) {
            "tl" -> setOf("tl", "fil")
            "ceb" -> setOf("ceb")
            else -> return null
        }
        return engine?.voices?.filter {
            it.locale.language in codes && !it.isNetworkConnectionRequired &&
                it.features?.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED) != true
        }?.sortedWith(compareByDescending<Voice> { it.quality }.thenBy { it.latency }.thenBy { it.name })?.firstOrNull()
    }
    private fun complete(id: String?, error: String?) { main.post {
        val pending = speaking
        if (pending != null && pending.first == id) {
            speaking = null
            if (error == null) pending.second.success(null)
            else pending.second.error("voice", error, null)
        }
    } }
    private fun stop() {
        engine?.stop()
        speaking?.second?.success(null)
        speaking = null
    }
    override fun close() {
        closed = true
        main.removeCallbacks(initializationTimeout)
        stop()
        val callbacks = waiting.toList()
        waiting.clear()
        callbacks.forEach { it() }
        engine?.shutdown()
        engine = null
        channel.setMethodCallHandler(null)
    }
}
