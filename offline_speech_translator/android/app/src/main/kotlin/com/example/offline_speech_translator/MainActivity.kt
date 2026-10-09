package com.example.offline_speech_translator

import android.content.Intent
import android.view.WindowManager
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var translation: OfflineTranslation? = null
    private var voice: OfflineVoice? = null
    private var cebuano: CebuanoModelImport? = null
    private var noise: NoiseCapture? = null
    private var activityState: MethodChannel? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        activityState = MethodChannel(messenger, "sulti/activity_state").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "keepScreenOn") {
                    if (call.arguments == true) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success(null)
                } else result.notImplemented()
            }
        }
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
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        activityState?.setMethodCallHandler(null)
        activityState = null
        cebuano?.close()
        noise?.close()
        voice?.close()
        translation?.close()
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
