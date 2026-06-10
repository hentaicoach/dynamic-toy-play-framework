import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// BLE 连接抽象 — 封装一个已连接的玩具设备的读写操作
class BleConnection {
  final BluetoothDevice _device;
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;

  final String deviceId;
  final String deviceName;

  /// 连接后自动发现的 Service UUID
  String? discoveredServiceUuid;

  bool get isConnected => _device.isConnected;
  BluetoothDevice get device => _device;

  final StreamController<List<int>> _notifyController =
      StreamController<List<int>>.broadcast();
  Stream<List<int>> get notifications => _notifyController.stream;

  BleConnection({
    required this.deviceId,
    required this.deviceName,
    required BluetoothDevice device,
  }) : _device = device;

  /// 已知的 YOKONEX 玩具 Service UUID
  static const _knownServices = [
    '0000ff40-0000-1000-8000-00805f9b34fb',
    '0000ff30-0000-1000-8000-00805f9b34fb',
    '0000ffb0-0000-1000-8000-00805f9b34fb',
  ];

  static const _serviceToChars = {
    '0000ff40-0000-1000-8000-00805f9b34fb': _CharMap(
      write: '0000ff41-0000-1000-8000-00805f9b34fb',
      notify: '0000ff42-0000-1000-8000-00805f9b34fb',
    ),
    '0000ff30-0000-1000-8000-00805f9b34fb': _CharMap(
      write: '0000ff31-0000-1000-8000-00805f9b34fb',
      notify: '0000ff32-0000-1000-8000-00805f9b34fb',
    ),
    '0000ffb0-0000-1000-8000-00805f9b34fb': _CharMap(
      write: '0000ffb1-0000-1000-8000-00805f9b34fb',
      notify: '0000ffb2-0000-1000-8000-00805f9b34fb',
    ),
  };

  /// 连接 + 自动发现服务（从已知 YOKONEX UUID 中匹配）
  Future<void> autoConnectAndDiscover({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    await _device.connect(timeout: timeout);
    final services = await _device.discoverServices();
    debugPrint('[BLE-CONN] ${device.platformName} 发现 ${services.length} 个服务');

    for (final svc in services) {
      final svcUuid = svc.uuid.toString().toLowerCase();
      debugPrint('[BLE-CONN]   Service: $svcUuid');

      // 匹配已知 YOKONEX 服务
      for (final known in _knownServices) {
        if (svcUuid.contains(known.substring(4, 8)) || // 短格式 ff40
            svcUuid == known.toLowerCase() ||          // 完整格式
            svc.uuid.str128.toLowerCase() == known) {
          discoveredServiceUuid = known;
          final chars = _serviceToChars[known]!;
          debugPrint('[BLE-CONN]   ✅ 匹配到 YOKONEX 服务: $known');

          for (final chr in svc.characteristics) {
            final chrUuid = chr.uuid.toString().toLowerCase();
            final targetWrite = chars.write.toLowerCase();
            final targetNotify = chars.notify?.toLowerCase();

            if (chrUuid.contains(targetWrite.substring(4, 8)) ||
                chrUuid == targetWrite ||
                chr.uuid.str128.toLowerCase() == targetWrite) {
              _writeChar = chr;
              debugPrint('[BLE-CONN]     Write Char: $chrUuid ✅');
            }
            if (targetNotify != null &&
                (chrUuid.contains(targetNotify.substring(4, 8)) ||
                    chrUuid == targetNotify ||
                    chr.uuid.str128.toLowerCase() == targetNotify)) {
              _notifyChar = chr;
              debugPrint('[BLE-CONN]     Notify Char: $chrUuid ✅');
            }
          }

          if (_writeChar != null) break; // 找到就跳出外层循环
        }
      }
      if (_writeChar != null) break;
    }

    if (_writeChar == null) {
      throw Exception('BLE: 未找到 YOKONEX 服务特征值 (device=$deviceName)');
    }

    if (_notifyChar != null) {
      await _notifyChar!.setNotifyValue(true);
      _notifyChar!.onValueReceived.listen((data) {
        debugPrint('[BLE-CONN] Notify 收到: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        _notifyController.add(data);
      });
    }
  }

  /// 旧版：根据指定 UUID 连接（保留兼容）
  Future<void> connectAndDiscover({
    required String serviceUuid,
    required String writeCharUuid,
    String? notifyCharUuid,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    await _device.connect(timeout: timeout);
    final services = await _device.discoverServices();

    for (final svc in services) {
      if (svc.uuid.toString().toLowerCase() == serviceUuid.toLowerCase() ||
          svc.uuid.str128.toLowerCase() == serviceUuid.toLowerCase()) {
        for (final chr in svc.characteristics) {
          final chrUuid = chr.uuid.toString().toLowerCase();
          final targetWrite = writeCharUuid.toLowerCase();
          final targetNotify = notifyCharUuid?.toLowerCase();

          if (chrUuid == targetWrite ||
              chr.uuid.str128.toLowerCase() == targetWrite) {
            _writeChar = chr;
          }
          if (targetNotify != null &&
              (chrUuid == targetNotify ||
                  chr.uuid.str128.toLowerCase() == targetNotify)) {
            _notifyChar = chr;
          }
        }
        break;
      }
    }

    if (_writeChar == null) {
      throw Exception('BLE: 未找到写特征值 $writeCharUuid (device=$deviceName)');
    }

    if (_notifyChar != null) {
      await _notifyChar!.setNotifyValue(true);
      _notifyChar!.onValueReceived.listen((data) {
        _notifyController.add(data);
      });
    }
  }

  Future<void> write(List<int> data) async {
    if (_writeChar == null) {
      throw Exception('BLE: 写特征值未初始化 (device=$deviceName)');
    }
    await _writeChar!.write(data, withoutResponse: true);
  }

  Future<void> disconnect() async {
    await _notifyController.close();
    try { await _device.disconnect(); } catch (_) {}
  }
}

/// 特征值映射
class _CharMap {
  final String write;
  final String? notify;
  const _CharMap({required this.write, this.notify});
}
