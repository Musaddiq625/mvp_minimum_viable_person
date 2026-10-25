package com.musaddiq625.mvp

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "mvp/net"
        ).setMethodCallHandler { call, result ->
            if (call.method == "status") {
                result.success(netStatus())
            } else {
                result.notImplemented()
            }
        }
    }

    // Real connectivity for the status chips. Airplane needs the settings
    // flag — connectivity alone can't tell it apart from "no signal".
    private fun netStatus(): String {
        val airplane = Settings.Global.getInt(
            contentResolver, Settings.Global.AIRPLANE_MODE_ON, 0
        ) == 1
        if (airplane) return "airplane"
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE)
            as ConnectivityManager
        val caps = cm.getNetworkCapabilities(cm.activeNetwork)
            ?: return "offline"
        return when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "data"
            else -> "offline"
        }
    }
}
