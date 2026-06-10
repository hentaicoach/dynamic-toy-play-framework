import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ble_connection.dart';

/// BLE 扫描结果模型
class BleScanResult {
  final String deviceId;
  final String deviceName;
  final int rssi;
  final String serviceUuid;

  BleScanResult({
    required this.deviceId,
    required this.deviceName,
    required this.rssi,
    required this.serviceUuid,
  });
}

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

  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  BluetoothAdapterState get adapterState => _adapterState;

  final Map<String, BleConnection> _connections = {};
  Map<String, BleConnection> get connections => Map.unmodifiable(_connections);

  final StreamController<BleScanResult> _scanResults =
      StreamController<BleScanResult>.broadcast();
  Stream<BleScanResult> get scanResults => _scanResults.stream;

  final StreamController<String> _disconnectedStream =
      StreamController<String>.broadcast();
  Stream<String> get onDeviceDisconnected => _disconnectedStream.stream;

  StreamSubscription? _scanSubscription;
  bool _isScanning = false;
  bool get isScanning => _isScanning;

  Future<void> init() async {
    FlutterBluePlus.adapterState.listen((state) {
      _adapterState = state;
    });

    // 监听扫描状态变化，自动同步 _isScanning
    FlutterBluePlus.isScanning.listen((scanning) {
      _isScanning = scanning;
      debugPrint('[BLE-MGR] isScanning=$scanning');
    });

    await Future.delayed(const Duration(milliseconds: 500));
  }

  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    if (_isScanning) return;
    _isScanning = true;

    await FlutterBluePlus.stopScan();

    await FlutterBluePlus.startScan(
      timeout: timeout,
      androidScanMode: AndroidScanMode.lowLatency,
    );

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      debugPrint('[BLE-SCAN] 收到扫描结果批次: ${results.length} 个设备');
      for (final r in results) {
        final device = r.device;
        final name = device.platformName.isNotEmpty
            ? device.platformName
            : '(无名称)';
        final id = device.remoteId.str;

        // 提取广播的 Service UUID（来自标准 UUID 和 Service Data 两种格式）
        final advUuids = r.advertisementData.serviceUuids;
        final advServiceDataKeys = r.advertisementData.serviceData.keys;
        final allUuids = [
          ...advUuids.map((g) => g.toString()),
          ...advServiceDataKeys.map((g) => g.toString()),
        ];
        final serviceUuid = allUuids.isNotEmpty ? allUuids.first : '';
        debugPrint('[BLE-SCAN]   -> $name ($id) RSSI=${r.rssi} UUIDs=$allUuids');

        // 不限制 UUID，所有设备都展示，记录广播的 Service UUID
        _scanResults.add(BleScanResult(
          deviceId: id,
          deviceName: name,
          rssi: r.rssi,
          serviceUuid: serviceUuid,
        ));
      }
      print(''); // 空行分隔
    });
    debugPrint('[BLE-SCAN] 扫描监听已注册');
  }

  Future<void> stopScan() async {
    _isScanning = false;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await FlutterBluePlus.stopScan();
  }

  Future<BleConnection> connect({
    required String deviceId,
    required String deviceName,
    required String serviceUuid,
  }) async {
    if (_connections.containsKey(deviceId)) {
      return _connections[deviceId]!;
    }

    final device = _findDevice(deviceId);
    if (device == null) {
      throw Exception('BLE: 未找到设备 $deviceName ($deviceId)');
    }

    final conn = BleConnection(
      deviceId: deviceId,
      deviceName: deviceName,
      device: device,
    );

    // 如果广播 Service UUID 为空，用 autoConnectAndDiscover 自动匹配
    if (serviceUuid.isEmpty) {
      debugPrint('[BLE-MGR] 广播 UUID 为空，自动发现服务...');
      await conn.autoConnectAndDiscover();
    } else {
      final charUuids = _getCharUuids(serviceUuid);
      if (charUuids == null) {
        debugPrint('[BLE-MGR] 广播 UUID "$serviceUuid" 不在已知列表，尝试自动发现...');
        await conn.autoConnectAndDiscover();
      } else {
        await conn.connectAndDiscover(
          serviceUuid: serviceUuid,
          writeCharUuid: charUuids.write,
          notifyCharUuid: charUuids.notify,
        );
      }
    }

    _connections[deviceId] = conn;

    device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _connections.remove(deviceId);
        _disconnectedStream.add(deviceId);
      }
    });

    return conn;
  }

  Future<void> disconnect(String deviceId) async {
    final conn = _connections.remove(deviceId);
    if (conn != null) await conn.disconnect();
  }

  Future<void> disconnectAll() async {
    final ids = _connections.keys.toList();
    for (final id in ids) { await disconnect(id); }
  }

  BleConnection? getConnection(String deviceId) => _connections[deviceId];

  _CharUuids? _getCharUuids(String serviceUuid) {
    final u = serviceUuid.toLowerCase();

    // 支持短格式（如 ff40）和完整格式（如 0000ff40-0000-1000-8000-00805f9b34fb）
    if (u.contains('ff40')) {
      return _CharUuids(write: '0000ff41-0000-1000-8000-00805f9b34fb', notify: '0000ff42-0000-1000-8000-00805f9b34fb');
    }
    if (u.contains('ff30')) {
      return _CharUuids(write: '0000ff31-0000-1000-8000-00805f9b34fb', notify: '0000ff32-0000-1000-8000-00805f9b34fb');
    }
    if (u.contains('ffb0')) {
      return _CharUuids(write: '0000ffb1-0000-1000-8000-00805f9b34fb', notify: '0000ffb2-0000-1000-8000-00805f9b34fb');
    }

    debugPrint('[BLE-MGR] 未知 Service UUID: $serviceUuid');
    return null;
  }

  BluetoothDevice? _findDevice(String deviceId) {
    try {
      final devices = FlutterBluePlus.connectedDevices;
      for (final d in devices) {
        if (d.remoteId.str == deviceId) return d;
      }
    } catch (_) {}
    try {
      return BluetoothDevice(remoteId: DeviceIdentifier(deviceId));
    } catch (_) {
      return null;
    }
  }

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
