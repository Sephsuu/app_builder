package com.example.offline_speech_translator

import android.content.Context
import android.app.ActivityManager
import android.os.Handler
import android.os.Looper
import ai.onnxruntime.OrtSession
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicBoolean

class OfflineTranslation(context: Context, messenger: BinaryMessenger) : AutoCloseable {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val timeout = Executors.newSingleThreadScheduledExecutor()
    private val generation = AtomicLong()
    private val models = TranslationModels(File(context.noBackupFilesDir, "nllb-$VERSION"), context.assets)
    private val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
    private val methods = MethodChannel(messenger, "sulti/offline_translation")
    private val events = EventChannel(messenger, "sulti/model_download")
    private var sink: EventChannel.EventSink? = null
    private val runLock = Any()
    private var activeRun: OrtSession.RunOptions? = null
    @Volatile private var closed = false
    companion object { private const val VERSION = "261c31d-int8" }

    init {
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
            override fun onCancel(arguments: Any?) { sink = null }
        })
        methods.setMethodCallHandler { call, result ->
            when (call.method) {
                "cancel" -> {
                    cancel()
                    // A fence: only complete after the current native job closes
                    // its sessions, so recording may safely load Whisper next.
                    worker.execute { main.post { result.success(null) } }
                }
                "isInstalled", "install", "translate" -> {
                    val token = generation.get()
                    worker.execute {
                        try {
                            fun checkCurrent() {
                                // A direction change invalidates text work, not
                                // the read-only model availability result.
                                check(!closed && (call.method == "isInstalled" || token == generation.get())) {
                                    "Operation cancelled."
                                }
                            }
                            checkCurrent()
                            val value: Any? = when (call.method) {
                                "isInstalled" -> models.installed(::checkCurrent)
                                "install" -> {
                                    require64Bit()
                                    models.install({ fraction -> main.post { sink?.success(fraction) } }, ::checkCurrent)
                                    null
                                }
                                else -> {
                                    require64Bit()
                                    requireAvailableMemory()
                                    val run = OrtSession.RunOptions()
                                    val timedOut = AtomicBoolean(false)
                                    synchronized(runLock) { activeRun = run }
                                    val alarm = timeout.schedule({
                                        synchronized(runLock) {
                                            if (activeRun === run) {
                                                timedOut.set(true)
                                                run.setTerminate(true)
                                            }
                                        }
                                    }, 120, TimeUnit.SECONDS)
                                    try {
                                        NllbTranslator(models).translate(
                                            call.argument<String>("text") ?: "",
                                            call.argument<String>("source") ?: "",
                                            call.argument<String>("target") ?: "",
                                            run, ::checkCurrent)
                                    } catch (error: Exception) {
                                        if (timedOut.get()) throw IllegalStateException(
                                            "Translation took too long on this phone. Try a shorter sentence; your source text is retained.", error)
                                        throw error
                                    } finally {
                                        alarm.cancel(false)
                                        synchronized(runLock) { activeRun = null; run.close() }
                                    }
                                }
                            }
                            checkCurrent()
                            main.post { result.success(value) }
                        } catch (error: Exception) {
                            main.post { result.error("translation", error.message ?: "Translation unavailable.", null) }
                        } catch (error: OutOfMemoryError) {
                            main.post { result.error("memory", "Insufficient memory for NLLB on this device.", null) }
                        } catch (error: LinkageError) {
                            main.post { result.error("runtime", "Translation runtime unavailable for this device: ${error.message}", null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    private fun cancel() {
        generation.incrementAndGet()
        synchronized(runLock) { activeRun?.setTerminate(true) }
    }
    private fun require64Bit() {
        check(android.os.Process.is64Bit()) {
            "This NLLB model requires a 64-bit Android process. Speech recognition remains available."
        }
    }
    private fun requireAvailableMemory() {
        val memory = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memory)
        // Conservative admission check, not a guarantee against OS reclamation.
        // Catching OutOfMemoryError cannot catch Android's low-memory process kill.
        val required = 768L * 1024 * 1024 + maxOf(memory.threshold, 128L * 1024 * 1024)
        check(!memory.lowMemory && memory.availMem >= required) {
            "Not enough free RAM for offline translation. Close other apps and retry; your source text is retained."
        }
    }
    override fun close() {
        closed = true
        cancel()
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        sink = null
        worker.shutdown()
        timeout.shutdownNow()
    }
}
