package com.example.yokonex_play

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import androidx.core.content.ContextCompat
import android.Manifest
import android.os.Build

class MainActivity: FlutterActivity() {

    private var bleScanBridge: BleScanBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val bridge = BleScanBridge(this, flutterEngine)
        bridge.register()
        bleScanBridge = bridge
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            1001 -> {
                val granted = grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
                bleScanBridge?.onPermissionResult(granted)
            }
            1002 -> {
                // 检查所有申请的权限是否都已授权
                val granted = grantResults.isNotEmpty() &&
                    grantResults.all { it == PackageManager.PERMISSION_GRANTED }
                bleScanBridge?.onLocationPermissionResult(granted)
            }
        }
    }
}
