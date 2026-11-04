package dev.fretlight.fretlight

import android.content.Context
import android.media.AudioManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The `record` plugin passes the requested audio source straight to
        // AudioRecord. UNPROCESSED is only guaranteed raw on devices that
        // declare support, so Dart asks here before choosing it.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fretlight/audio_caps")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "supportsUnprocessed" -> {
                        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        result.success(
                            audio.getProperty(AudioManager.PROPERTY_SUPPORT_AUDIO_SOURCE_UNPROCESSED) == "true"
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
