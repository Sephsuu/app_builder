package com.example.offline_speech_translator

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var translation: OfflineTranslation? = null
    private var voice: OfflineVoice? = null
    private var cebuano: CebuanoModelImport? = null
    private var noise: NoiseCapture? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        translation = OfflineTranslation(applicationContext, messenger)
        voice = OfflineVoice(applicationContext, messenger)
        cebuano = CebuanoModelImport(this, messenger)
        noise = NoiseCapture(applicationContext, messenger)
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (cebuano?.onResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        cebuano?.close()
        noise?.close()
        voice?.close()
        translation?.close()
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
