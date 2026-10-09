package com.example.offline_speech_translator

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

/** Imports only the evaluated research GGML derivative, never arbitrary models. */
class CebuanoModelImport(private val activity: Activity, messenger: BinaryMessenger) : AutoCloseable {
    private val channel = MethodChannel(messenger, "sulti/cebuano_model")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private val file get() = File(activity.filesDir, "whisper_models/ggml-cebuano-small-q5_1.bin")
    companion object {
        const val REQUEST = 7614
        const val SHA = "43b3973c2baaff647a92619102c24e3dd0ed1f0e00993b7e3ecd68231dfc587f"
        const val SIZE = 190085487L
    }
    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "find" -> worker.execute {
                    val found = try { if (valid(file)) file.absolutePath else null } catch (_: Exception) { null }
                    main.post { result.success(found) }
                }
                "import" -> {
                    if (pending != null) result.error("busy", "An import is already open.", null)
                    else {
                        pending = result
                        try {
                            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "*/*"
                            }, REQUEST)
                        } catch (error: Exception) {
                            pending = null
                            result.error("import", error.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    private fun valid(candidate: File): Boolean {
        if (!candidate.isFile || candidate.length() != SIZE) return false
        val digest = MessageDigest.getInstance("SHA-256")
        candidate.inputStream().use { input ->
            val buffer = ByteArray(1024 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) } == SHA
    }
    fun onResult(request: Int, code: Int, data: Intent?): Boolean {
        if (request != REQUEST) return false
        val result = pending ?: return true
        val uri = data?.data
        if (code != Activity.RESULT_OK || uri == null) {
            pending = null
            result.success(false)
            return true
        }
        worker.execute {
            val partial = File(file.parentFile, file.name + ".import")
            try {
                file.parentFile!!.mkdirs()
                activity.contentResolver.openInputStream(uri)?.use { input ->
                    partial.outputStream().use { output ->
                        val buffer = ByteArray(1024 * 1024)
                        var total = 0L
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            total += count
                            require(total <= SIZE) { "Choose the converted Cebuano Q5_1 model (190 MB)." }
                            output.write(buffer, 0, count)
                        }
                    }
                } ?: error("The selected file cannot be opened.")
                check(valid(partial)) { "This is not the verified Cebuano Q5_1 model. Choose ggml-cebuano-small-q5_1.bin." }
                check(partial.renameTo(file)) { "Could not save the model. Check free storage and retry." }
                main.post { if (pending === result) { pending = null; result.success(true) } }
            } catch (error: Exception) {
                main.post { if (pending === result) { pending = null; result.error("import", error.message, null) } }
            } finally { partial.delete() }
        }
        return true
    }
    override fun close() {
        channel.setMethodCallHandler(null)
        pending?.error("closed", "Model import was interrupted. Retry after reopening the app.", null)
        pending = null
        worker.shutdown()
    }
}
