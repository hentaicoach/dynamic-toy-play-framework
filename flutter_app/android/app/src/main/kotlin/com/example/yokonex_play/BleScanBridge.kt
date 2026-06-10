package com.example.yokonex_play

import android.Manifest
import android.app.Activity
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * BLE 扫描桥 — 扫描前自动请求权限
 */
class BleScanBridge(private val context: Context, private val engine: FlutterEngine) {

    companion object {
        const val CHANNEL = "com.example.yokonex_play/ble_scan"
        private const val PERMISSION_REQUEST_CODE = 1001
        private const val LOCATION_PERMISSION_REQUEST_CODE = 1002
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var bluetoothLeScanner: BluetoothLeScanner? = null
    private val foundDevices = mutableMapOf<String, Map<String, Any>>()
    @Volatile private var isScanning = false
    private var scanCallback: ScanCallback? = null
    private var pendingChannel: MethodChannel? = null
    private var pendingLocationResult: MethodChannel.Result? = null

    fun register() {
        val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? android.bluetooth.BluetoothManager
        bluetoothLeScanner = manager?.adapter?.bluetoothLeScanner

        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "scan" -> doScan(channel)
                "isBtEnabled" -> result.success(manager?.adapter?.isEnabled == true)
                "isLocationEnabled" -> {
                    val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as? android.location.LocationManager
                    val isGpsEnabled = locationManager?.isProviderEnabled(android.location.LocationManager.GPS_PROVIDER) == true
                    val isNetworkEnabled = locationManager?.isProviderEnabled(android.location.LocationManager.NETWORK_PROVIDER) == true
                    result.success(isGpsEnabled || isNetworkEnabled)
                }
                "requestLocationPermission" -> {
                    requestLocationPermission(result)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun doScan(channel: MethodChannel) {
        if (isScanning) return

        // 检查并请求权限
        if (!checkBlePermissions()) {
            pendingChannel = channel
            requestBlePermissions()
            return
        }

        startScanInternal(channel)
    }

    private fun checkBlePermissions(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        }
        return true
    }

    private fun requestBlePermissions() {
        val activity = context as? Activity ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ActivityCompat.requestPermissions(activity,
                arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT),
                PERMISSION_REQUEST_CODE)
        } else {
            ActivityCompat.requestPermissions(activity,
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION),
                PERMISSION_REQUEST_CODE)
        }
    }

    /** 请求所有 BLE+定位需要的权限 */
    private fun requestLocationPermission(result: MethodChannel.Result) {
        val activity = context as? Activity ?: run {
            result.success(false)
            return
        }
        // 如果已经全部授权，直接返回成功
        if (allBlePermissionsGranted()) {
            result.success(true)
            return
        }
        pendingLocationResult = result
        val permissions = buildList {
            add(Manifest.permission.ACCESS_FINE_LOCATION)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                add(Manifest.permission.BLUETOOTH_SCAN)
                add(Manifest.permission.BLUETOOTH_CONNECT)
            }
        }
        ActivityCompat.requestPermissions(activity,
            permissions.toTypedArray(),
            LOCATION_PERMISSION_REQUEST_CODE)
    }

    private fun allBlePermissionsGranted(): Boolean {
        val perms = buildList {
            add(Manifest.permission.ACCESS_FINE_LOCATION)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                add(Manifest.permission.BLUETOOTH_SCAN)
                add(Manifest.permission.BLUETOOTH_CONNECT)
            }
        }
        return perms.all { ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED }
    }

    /** 由 MainActivity 在 onRequestPermissionsResult 中调用 */
    fun onPermissionResult(granted: Boolean) {
        val channel = pendingChannel
        pendingChannel = null
        if (granted) {
            startScanInternal(channel)
        } else {
            channel?.invokeMethod("onError", "用户拒绝了蓝牙权限，请在系统设置中手动开启")
        }
    }

    /** 由 MainActivity 在 onRequestPermissionsResult 中调用（定位权限） */
    fun onLocationPermissionResult(granted: Boolean) {
        val result = pendingLocationResult
        pendingLocationResult = null
        result?.success(granted)
    }

    private fun startScanInternal(channel: MethodChannel?) {
        if (channel == null) return
        isScanning = true
        foundDevices.clear()

        val scanner = bluetoothLeScanner ?: run {
            channel.invokeMethod("onError", "BLE 扫描器不可用")
            isScanning = false
            return
        }

        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult?) {
                val device = result?.device ?: return
                val name = device.name ?: ""
                android.util.Log.d("[BLE-NATIVE]", "onScanResult: name='$name' addr=${device.address} rssi=${result.rssi}")
                // 即使无名称也显示MAC地址
                foundDevices[device.address] = mapOf(
                    "name" to (name.ifEmpty { "(无名称)" }),
                    "address" to device.address,
                    "rssi" to result.rssi
                )
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>?) {
                android.util.Log.d("[BLE-NATIVE]", "onBatchScanResults: ${results?.size}")
                results?.forEach { onScanResult(0, it) }
            }

            override fun onScanFailed(errorCode: Int) {
                android.util.Log.e("[BLE-NATIVE]", "扫描失败 code=$errorCode")
                channel.invokeMethod("onError", "扫描失败 code=$errorCode")
                if (isScanning) {
                    isScanning = false
                    try { scanner.stopScan(this) } catch (_: Exception) {}
                }
            }
        }
        scanCallback = callback

        try {
            scanner.startScan(null, settings, callback)
            mainHandler.postDelayed({
                if (isScanning) {
                    isScanning = false
                    try { scanner.stopScan(callback) } catch (_: Exception) {}
                    scanCallback = null
                    channel.invokeMethod("onResults", foundDevices.values.toList())
                }
            }, 5000)
        } catch (e: SecurityException) {
            channel.invokeMethod("onError", "缺少权限: ${e.message}")
            isScanning = false
            scanCallback = null
        } catch (e: Exception) {
            channel.invokeMethod("onError", "扫描异常: ${e.message}")
            isScanning = false
            scanCallback = null
        }
    }
}
