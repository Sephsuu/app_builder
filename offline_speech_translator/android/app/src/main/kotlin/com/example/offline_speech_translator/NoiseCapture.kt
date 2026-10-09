package com.example.offline_speech_translator

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.NoiseSuppressor
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Experimental opt-in effect. Original plugin recorder remains the default. */
class NoiseCapture(private val context: Context, messenger: BinaryMessenger) : AutoCloseable {
    private val methods = MethodChannel(messenger, "sulti/noise_capture")
    private val events = EventChannel(messenger, "sulti/noise_audio")
    private val main = Handler(Looper.getMainLooper())
    private val cleanup = Executors.newSingleThreadExecutor()
    private var sink: EventChannel.EventSink? = null
    private var recorder: AudioRecord? = null
    private var effect: NoiseSuppressor? = null
    private var reader: Thread? = null
    private val running = AtomicBoolean(false)
    private var stopping = false

    init {
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
            override fun onCancel(arguments: Any?) { sink = null }
        })
        methods.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> try { result.success(start()) }
                    catch (error: Exception) { result.error("audio", error.message, null) }
                "stop" -> stop { failure ->
                    if (failure == null) result.success(null)
                    else result.error("audio", failure, null)
                }
                else -> result.notImplemented()
            }
        }
    }
    private fun start(): Boolean {
        check(!stopping && recorder == null) { "Recorder is busy." }
        check(context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            "Microphone permission is required."
        }
        if (!NoiseSuppressor.isAvailable()) return false
        val minimum = AudioRecord.getMinBufferSize(16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_FLOAT)
        if (minimum <= 0) return false
        val sampleCount = maxOf(1600, (minimum + 3) / 4)
        val audio = AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, 16000,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_FLOAT, sampleCount * 4)
        var suppressor: NoiseSuppressor? = null
        try {
            if (audio.state != AudioRecord.STATE_INITIALIZED) return false
            suppressor = NoiseSuppressor.create(audio.audioSessionId) ?: return false
            if (!suppressor.hasControl() || suppressor.setEnabled(true) != 0 || !suppressor.enabled) return false
            audio.startRecording()
            check(audio.recordingState == AudioRecord.RECORDSTATE_RECORDING) { "Microphone could not start." }
            recorder = audio
            effect = suppressor
            running.set(true)
            reader = Thread({
                val buffer = FloatArray(sampleCount)
                try {
                    while (running.get()) {
                        val count = audio.read(buffer, 0, buffer.size, AudioRecord.READ_BLOCKING)
                        if (count <= 0) {
                            if (running.get()) error("Microphone read failed ($count).")
                            break
                        }
                        val bytes = ByteBuffer.allocate(count * 4).order(ByteOrder.LITTLE_ENDIAN)
                        for (index in 0 until count) bytes.putFloat(buffer[index])
                        main.post { sink?.success(bytes.array()) }
                    }
                } catch (error: Exception) {
                    main.post { sink?.error("audio", error.message, null) }
                }
            }, "sulti-noise-capture").also { it.start() }
            return true
        } finally {
            if (recorder !== audio) { suppressor?.release(); audio.release() }
        }
    }
    private fun stop(done: (String?) -> Unit) {
        stopping = true
        running.set(false)
        val audio = recorder
        val thread = reader
        val suppressor = effect
        recorder = null
        reader = null
        effect = null
        cleanup.execute {
            var failure: String? = null
            var released = false
            try {
                try {
                    if (audio?.recordingState == AudioRecord.RECORDSTATE_RECORDING) audio.stop()
                } catch (error: Exception) {
                    failure = error.message ?: "Could not stop microphone capture."
                    // Release unblocks a failed read before joining the worker.
                    audio?.release()
                    released = true
                }
                thread?.join()
            } finally {
                suppressor?.release()
                if (!released) audio?.release()
                // Captured chunks were posted first; this fence drains them before
                // Dart closes the stream and assembles the final recording.
                main.post { stopping = false; done(failure) }
            }
        }
    }
    override fun close() {
        stop { cleanup.shutdown() }
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        sink = null
    }
}
