import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ble_connection.dart';
import '../../config/constants.dart';

/// BLE 扫描结果模型
class BleScanResult {
  final String deviceId;
  final String deviceName;
  final int rssi;
  final String serviceUuid; // 匹配的服务 UUID

  BleScanResult({
    required this.deviceId,
    required this.deviceName,
    required this.rssi,
    required this.serviceUuid,
  });
}

/// 已知玩具的 BLE service UUID → 玩具类型映射
const Map<String, String> kServiceToToyType = {
  '0000ff40-0000-1000-8000-00805f9b34fb': 'vibrator',
  '0000ff30-0000-1000-8000-00805f9b34fb': 'ems',
  '0000ffb0-0000-1000-8000-00805f9b34fb': 'enema',
};

/// BLE 管理器 — 包装 FlutterBluePlus
class BleManager {
  static final BleManager _instance = BleManager._();
  factory BleManager() => _instance;
  BleManager._();

  /// 当前蓝牙适配器状态
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  BluetoothAdapterState get adapterState => _adapterState;

  /// 已连接的设备
  final Map<String, BleConnection> _connections = {};
  Map<String, BleConnection> get connections =>
      Map.unmodifiable(_connections);

  /// 扫描结果流
  final StreamController<BleScanResult> _scanResults =
      StreamController<BleScanResult>.broadcast();
  Stream<BleScanResult> get scanResults => _scanResults.stream;

  /// 连接状态变化流
  final StreamController<String> _disconnectedStream =
      StreamController<String>.broadcast();
  Stream<String> get onDeviceDisconnected => _disconnectedStream.stream;

  StreamSubscription? _scanSubscription;
  bool _isScanning = false;
  bool get isScanning => _isScanning;

  /// 初始化 BLE 适配器监听
  Future<void> init() async {
    FlutterBluePlus.adapterState.listen((state) {
      _adapterState = state;
    });
  }

  /// 开始扫描（过滤已知玩具 Service UUID）
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    if (_isScanning) return;
    _isScanning = true;

    // 先停旧的扫描
    await FlutterBluePlus.stopScan();

    // 构建过滤 UUID 列表
    final filterUuids = kServiceToToyType.keys
        .map((u) => Guid(u))
        .toList();

    // 设置扫描模式
    await FlutterBluePlus.startScan(
      timeout: timeout,
      androidScanMode: AndroidScanMode.lowLatency,
      // 注意：某些设备广播可能不带完整 service UUID，所以不强制 uuidFilter
    );

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final device = r.device;
        final name = device.platformName.isNotEmpty
            ? device.platformName
            : device.remoteId.str;
        final id = device.remoteId.str;

        // 按已知 UUID 匹配
        String? matchedUuid;
        for (final svcUuid in kServiceToToyType.keys) {
          final guid = Guid(svcUuid);
          if (r.advertisementData.serviceUuids
              .any((u) => u.str128.toLowerCase() == guid.str128.toLowerCase())) {
            matchedUuid = svcUuid;
            break;
          }
        }
        // 如果广播里没有 service UUID 但设备名包含关键词，也展示
        if (matchedUuid == null) {
          final lowerName = name.toLowerCase();
          if (lowerName.contains('ycy') ||
              lowerName.contains('yskj') ||
              lowerName.contains('toy') ||
              lowerName.contains('ble')) {
            // 显示但不匹配具体类型
          }
        }

        if (matchedUuid != null) {
          _scanResults.add(BleScanResult(
            deviceId: id,
            deviceName: name,
            rssi: r.rssi,
            serviceUuid: matchedUuid,
          ));
        }
      }
    });

    // 超时后自动停止
    await Future.delayed(timeout);
    await stopScan();
  }

  /// 停止扫描
  Future<void> stopScan() async {
    _isScanning = false;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await FlutterBluePlus.stopScan();
  }

  /// 连接设备 — 根据 service UUID 自动发现特征值
  Future<BleConnection> connect({
    required String deviceId,
    required String deviceName,
    required String serviceUuid,
  }) async {
    // 如果已有连接则返回
    if (_connections.containsKey(deviceId)) {
      return _connections[deviceId]!;
    }

    // 从扫描结果找设备
    final device = await _findDevice(deviceId);
    if (device == null) {
      throw Exception('BLE: 未找到设备 $deviceName ($deviceId)');
    }

    // 获取目标特征值 UUID
    final charUuids = _getCharUuids(serviceUuid);
    if (charUuids == null) {
      throw Exception('BLE: 未知的 Service UUID: $serviceUuid');
    }

    final conn = BleConnection(
      deviceId: deviceId,
      deviceName: deviceName,
      device: device,
    );

    await conn.connectAndDiscover(
      serviceUuid: serviceUuid,
      writeCharUuid: charUuids.write,
      notifyCharUuid: charUuids.notify,
    );

    _connections[deviceId] = conn;

    // 监听断开（1.29.0 用 connectionState 代替 onDisconnected）
    device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _connections.remove(deviceId);
        _disconnectedStream.add(deviceId);
      }
    });

    return conn;
  }

  /// 断开设备
  Future<void> disconnect(String deviceId) async {
    final conn = _connections.remove(deviceId);
    if (conn != null) {
      await conn.disconnect();
    }
  }

  /// 断开所有
  Future<void> disconnectAll() async {
    final ids = _connections.keys.toList();
    for (final id in ids) {
      await disconnect(id);
    }
  }

  /// 获取连接
  BleConnection? getConnection(String deviceId) => _connections[deviceId];

  // ════════════════════════════════════════════
  // 内部辅助
  // ════════════════════════════════════════════

  /// 根据 service UUID 获取对应的写/通知特征值 UUID
  _CharUuids? _getCharUuids(String serviceUuid) {
    switch (serviceUuid.toLowerCase()) {
      case '0000ff40-0000-1000-8000-00805f9b34fb':
        return _CharUuids(
          write: '0000ff41-0000-1000-8000-00805f9b34fb',
          notify: '0000ff42-0000-1000-8000-00805f9b34fb',
        );
      case '0000ff30-0000-1000-8000-00805f9b34fb':
        return _CharUuids(
          write: '0000ff31-0000-1000-8000-00805f9b34fb',
          notify: '0000ff32-0000-1000-8000-00805f9b34fb',
        );
      case '0000ffb0-0000-1000-8000-00805f9b34fb':
        return _CharUuids(
          write: '0000ffb1-0000-1000-8000-00805f9b34fb',
          notify: '0000ffb2-0000-1000-8000-00805f9b34fb',
        );
      default:
        return null;
    }
  }

  Future<BluetoothDevice?> _findDevice(String deviceId) async {
    // 尝试从已知系统设备查找
    try {
      final devices = FlutterBluePlus.connectedDevices;
      for (final d in devices) {
        if (d.remoteId.str == deviceId) return d;
      }
    } catch (_) {}
    // 如果是已知的 remoteId 设备
    try {
      return BluetoothDevice(remoteId: DeviceIdentifier(deviceId));
    } catch (_) {
      return null;
    }
  }

  /// 释放资源
  void dispose() {
    _scanSubscription?.cancel();
    _scanResults.close();
    _disconnectedStream.close();
  }
}

class _CharUuids {
  final String write;
  final String? notify;
  _CharUuids({required this.write, this.notify});
}
