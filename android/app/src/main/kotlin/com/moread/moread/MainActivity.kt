package com.moread.moread

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 阅读时保活屏幕，不用额外插件
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "moread/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "keepAwake" -> {
                        if (call.arguments as? Boolean == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
