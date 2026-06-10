import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// BLE 连接抽象 — 封装一个已连接的玩具设备的读写操作
class BleConnection {
  final BluetoothDevice _device;
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;

  /// 设备信息（连接前可用）
  final String deviceId;   // MAC 地址或 BLE ID
  final String deviceName; // BLE 广播名

  bool get isConnected => _device.isConnected;
  BluetoothDevice get device => _device;

  /// 订阅通知的广播流
  final StreamController<List<int>> _notifyController =
      StreamController<List<int>>.broadcast();
  Stream<List<int>> get notifications => _notifyController.stream;

  BleConnection({
    required this.deviceId,
    required this.deviceName,
    required BluetoothDevice device,
  }) : _device = device;

  /// 连接并发现指定 Service 的写/通知特征值
  Future<void> connectAndDiscover({
    required String serviceUuid,
    required String writeCharUuid,
    String? notifyCharUuid,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    // 连接
    await _device.connect(timeout: timeout);

    // 发现服务
    final services = await _device.discoverServices();

    // 查找目标 Service
    for (final svc in services) {
      if (svc.uuid.toString().toLowerCase() == serviceUuid.toLowerCase() ||
          svc.uuid.str128.toLowerCase() == serviceUuid.toLowerCase()) {
        for (final chr in svc.characteristics) {
          final chrUuid = chr.uuid.toString().toLowerCase();
          final targetWrite = writeCharUuid.toLowerCase();
          final targetNotify =
              notifyCharUuid?.toLowerCase();

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
      throw Exception(
        'BLE: 未找到写特征值 $writeCharUuid (service=$serviceUuid, device=$deviceName)',
      );
    }

    // 订阅通知
    if (_notifyChar != null) {
      await _notifyChar!.setNotifyValue(true);
      _notifyChar!.onValueReceived.listen((data) {
        _notifyController.add(data);
      });
    }
  }

  /// 写入数据（带 BLE 写入限频）
  Future<void> write(List<int> data) async {
    if (_writeChar == null) {
      throw Exception('BLE: 写特征值未初始化 (device=$deviceName)');
    }
    await _writeChar!.write(data, withoutResponse: true);
  }

  /// 写入数据并等待响应
  Future<void> writeWithResponse(List<int> data) async {
    if (_writeChar == null) {
      throw Exception('BLE: 写特征值未初始化 (device=$deviceName)');
    }
    await _writeChar!.write(data, withoutResponse: false);
  }

  /// 断开连接
  Future<void> disconnect() async {
    await _notifyController.close();
    try {
      await _device.disconnect();
    } catch (_) {}
  }

  /// 获取 MTU（用于大包拆分）
  Future<int> get mtu async => _device.mtuNow;

  /// 请求更大 MTU
  Future<void> requestMtu(int size) async {
    await _device.requestMtu(size);
  }
}
