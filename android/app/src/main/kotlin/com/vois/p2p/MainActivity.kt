// Vois native Android radio transport plugin
package com.vois.p2p

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private val p2pServer = P2pServerPlugin()
    private val wifiDirect = WifiDirectPlugin()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(p2pServer)
        flutterEngine.plugins.add(wifiDirect)
    }
}
