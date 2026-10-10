package com.example.offline_speech_translator

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** A user-supplied key: encrypted at rest and excluded from Android backups. */
class OnlineTranslationSettings(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "sulti/online_translation_settings")
    private val file = AtomicFile(File(context.noBackupFilesDir, "openai-key.enc"))
    private val alias = "sulti.openai.user-key.v1"

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "configured" -> result.success(file.baseFile.exists())
                    "isOnline" -> {
                        val manager = context.getSystemService(ConnectivityManager::class.java)
                        val capabilities = manager.getNetworkCapabilities(manager.activeNetwork)
                        result.success(capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true &&
                            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED))
                    }
                    "readKey" -> result.success(readKey())
                    "saveKey" -> {
                        val value = (call.arguments as? String)?.trim() ?: ""
                        require(value.startsWith("sk-") && value.length in 20..1024 && value.none { it.isWhitespace() })
                        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
                        val data = JSONObject().put("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
                            .put("ciphertext", Base64.encodeToString(cipher.doFinal(value.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP))
                            .toString().toByteArray(Charsets.UTF_8)
                        val stream = file.startWrite()
                        try {
                            stream.write(data)
                            file.finishWrite(stream)
                        } catch (error: Exception) {
                            file.failWrite(stream)
                            throw error
                        }
                        result.success(null)
                    }
                    "removeKey" -> { file.delete(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                // Do not include supplied values or cryptographic details in errors.
                result.error("online_settings", "Could not access the OpenAI key. Save a valid replacement key in settings.", null)
            }
        }
    }

    private fun secretKey(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256).build())
        }.generateKey()
    }

    private fun readKey(): String? {
        if (!file.baseFile.exists()) return null
        val data = JSONObject(file.openRead().use { String(it.readBytes(), Charsets.UTF_8) })
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, Base64.decode(data.getString("iv"), Base64.NO_WRAP)))
        return String(cipher.doFinal(Base64.decode(data.getString("ciphertext"), Base64.NO_WRAP)), Charsets.UTF_8)
    }

    fun close() = channel.setMethodCallHandler(null)
}
