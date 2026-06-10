import 'dart:async';
import 'package:flutter/services.dart';

/// 原生 BLE 扫描桥 — 极简，只扫描不连接
///
/// 5 秒超时，一次返回所有发现的设备。
class NativeBleScanner {
  static const _channel = MethodChannel('com.example.yokonex_play/ble_scan');

  static final NativeBleScanner _instance = NativeBleScanner._();
  factory NativeBleScanner() => _instance;
  NativeBleScanner._();

  /// 扫描 5 秒，返回发现的设备列表 [{name, address, rssi}]
  Future<List<Map<String, dynamic>>> scan() async {
    final completer = Completer<List<Map<String, dynamic>>>();
    final results = <Map<String, dynamic>>[];
    bool done = false;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onResults':
          if (!done) {
            final list = (call.arguments as List<dynamic>)
                .cast<Map<dynamic, dynamic>>();
            for (final item in list) {
              results.add(item.cast<String, dynamic>());
            }
            done = true;
            completer.complete(results);
          }
        case 'onError':
          if (!done) {
            done = true;
            completer.completeError(PermissionException(call.arguments as String));
          }
      }
    });

    // 超时兜底
    Future.delayed(const Duration(seconds: 8), () {
      if (!done) {
        done = true;
        completer.complete(results);
      }
    });

    try {
      await _channel.invokeMethod('scan');
    } catch (e) {
      if (!done) {
        done = true;
        completer.completeError(e);
      }
    }

    return completer.future;
  }

  Future<bool> isBluetoothEnabled() async {
    try {
      return await _channel.invokeMethod('isBtEnabled') as bool;
    } catch (_) {
      return false;
    }
  }

  /// 检查 Android 系统定位服务是否开启
  Future<bool> isLocationEnabled() async {
    try {
      return await _channel.invokeMethod('isLocationEnabled') as bool;
    } catch (_) {
      // 非 Android 或桥不可用时默认返回 true
      return true;
    }
  }

  /// 请求 Android 定位权限（部分 OEM 的 BLE 扫描要求这个）
  Future<bool> requestLocationPermission() async {
    try {
      return await _channel.invokeMethod('requestLocationPermission') as bool;
    } catch (_) {
      return false;
    }
  }
}

class PermissionException implements Exception {
  final String message;
  PermissionException(this.message);
  @override
  String toString() => message;
}
