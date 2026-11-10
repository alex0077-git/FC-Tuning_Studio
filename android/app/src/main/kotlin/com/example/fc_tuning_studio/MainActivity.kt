package com.example.fc_tuning_studio

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var g20Udp: G20UdpBridge? = null
    private var downloads: DownloadsBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        g20Udp = G20UdpBridge(messenger)
        downloads = DownloadsBridge(applicationContext, messenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        g20Udp?.close()
        g20Udp = null
        downloads?.close()
        downloads = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
