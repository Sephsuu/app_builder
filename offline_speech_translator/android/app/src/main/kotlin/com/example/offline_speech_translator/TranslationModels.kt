package com.example.offline_speech_translator

import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import android.content.res.AssetManager
import org.json.JSONObject

/** Only setup downloads use the network. Verified files are committed atomically. */
class TranslationModels(private val directory: File, private val packagedAssets: AssetManager) {
    data class Asset(val remote: String, val size: Long, val sha256: String) {
        val name get() = remote.substringAfterLast('/')
    }
    companion object {
        const val REVISION = "261c31d1a5732c67cdd16d80e8d6088507c7ccea"
        val assets = listOf(
            Asset("onnx/encoder_model_quantized.onnx", 419120483,
                "5cde664eacba07a62f198857ec6c06e09572b1ebb77c8137f1fa99ac604a3a28"),
            Asset("onnx/decoder_model_merged_quantized.onnx", 475505771,
                "dd66608c2a4194e78f95548fa0e64f24302303698c5b09fa8e1f9e16ec00676b"),
            Asset("sentencepiece.bpe.model", 4852054,
                "14bb8dfb35c0ffdea7bc01e56cea38b9e3d5efcdcb9c251d6b40538e1aab555a")
        )
    }
    private val verified = mutableMapOf<String, Pair<Long, Long>>()
    fun file(name: String) = File(directory, name)

    /** Small graphs reference byte ranges in the unchanged, verified downloads. */
    fun mobileGraph(name: String, checkCancelled: () -> Unit): File {
        require(name == "encoder_mobile.onnx" || name == "decoder_mobile.onnx")
        val manifest = packagedAssets.open("nllb-mobile/manifest.json").bufferedReader().use {
            JSONObject(it.readText())
        }
        check(manifest.getString("source_revision") == REVISION)
        val entries = manifest.getJSONArray("files")
        val metadata = (0 until entries.length()).map { entries.getJSONObject(it) }
            .single { it.getString("name") == name }
        val size = metadata.getLong("bytes")
        val sha = metadata.getString("sha256")
        val target = file(name)
        val stamp = target.length() to target.lastModified()
        if (target.isFile && target.length() == size &&
            (verified["mobile:$name"] == stamp || hash(target, checkCancelled) == sha)) {
            verified["mobile:$name"] = stamp
            return target
        }
        val partial = file("$name.part")
        try {
            packagedAssets.open("nllb-mobile/$name").use { input ->
                partial.outputStream().buffered().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        checkCancelled()
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                    }
                }
            }
            check(partial.length() == size && hash(partial, checkCancelled) == sha) {
                "The packaged translation graph could not be verified."
            }
            check(partial.renameTo(target)) { "Could not prepare the mobile translation graph." }
            verified["mobile:$name"] = target.length() to target.lastModified()
            return target
        } finally { partial.delete() }
    }

    fun installed(checkCancelled: () -> Unit = {}) = assets.all {
        valid(it, checkCancelled)
    }

    private fun valid(asset: Asset, checkCancelled: () -> Unit): Boolean {
        val f = file(asset.name)
        if (!f.isFile || f.length() != asset.size) return false
        val stamp = f.length() to f.lastModified()
        if (verified[asset.name] == stamp) return true
        if (hash(f, checkCancelled) != asset.sha256) return false
        verified[asset.name] = stamp
        return true
    }

    fun install(progress: (Double) -> Unit, checkCancelled: () -> Unit) {
        check(directory.isDirectory || directory.mkdirs()) { "Cannot create model storage." }
        val total = assets.sumOf { it.size }
        var completed = 0L
        for (asset in assets) {
            checkCancelled()
            if (valid(asset, checkCancelled)) {
                completed += asset.size
                progress(completed.toDouble() / total)
                continue
            }
            val partial = file("${asset.name}.part")
            var offset = if (partial.isFile && partial.length() < asset.size) partial.length() else 0L
            check(directory.usableSpace > asset.size - offset + 32_000_000) {
                "Not enough storage for the translation model (about 900 MB total)."
            }
            val url = "https://huggingface.co/Xenova/nllb-200-distilled-600M/resolve/$REVISION/${asset.remote}"
            val connection = URL(url).openConnection() as HttpURLConnection
            connection.connectTimeout = 30_000
            connection.readTimeout = 30_000
            if (offset > 0) connection.setRequestProperty("Range", "bytes=$offset-")
            try {
                val status = connection.responseCode
                check(status == 200 || status == 206) { "Model download failed (HTTP $status). Retry setup." }
                if (status == 200) offset = 0
                if (status == 206) check(connection.getHeaderField("Content-Range")
                    ?.startsWith("bytes $offset-") == true) { "Invalid resumed download." }
                connection.inputStream.buffered().use { input ->
                    java.io.FileOutputStream(partial, offset > 0).buffered().use { output ->
                        val buffer = ByteArray(64 * 1024)
                        var lastProgress = 0L
                        while (true) {
                            checkCancelled()
                            val count = input.read(buffer)
                            if (count < 0) break
                            offset += count
                            check(offset <= asset.size) { "Unexpected model download size." }
                            output.write(buffer, 0, count)
                            val now = System.nanoTime()
                            if (now - lastProgress > 100_000_000) {
                                progress((completed + offset).toDouble() / total)
                                lastProgress = now
                            }
                        }
                    }
                }
                check(partial.length() == asset.size) { "Download incomplete. Retry to resume." }
                if (hash(partial, checkCancelled) != asset.sha256) {
                    partial.delete()
                    error("Model checksum mismatch. Retry setup.")
                }
                check(partial.renameTo(file(asset.name))) { "Could not save verified model." }
                verified.remove(asset.name)
                completed += asset.size
                progress(completed.toDouble() / total)
            } finally { connection.disconnect() }
        }
    }

    private fun hash(file: File, checkCancelled: () -> Unit): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                checkCancelled()
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
    }
}
