import 'package:flutter/foundation.dart';
import 'drivers/toy_driver.dart';
import 'drivers/fake_drivers.dart';
import 'drivers/vibrator_driver.dart';
import 'drivers/ems_v1_driver.dart';
import 'drivers/ems_v2_driver.dart';
import 'drivers/enema_driver.dart';
import 'drivers/lock_driver.dart';
import 'ble_connection.dart';

/// 玩具配置，用于快速注册假驱动
class ToyConfig {
  final String toyId;
  final String toyName;
  final String type; // vibrator | ems | enema | lock

  const ToyConfig({
    required this.toyId,
    required this.toyName,
    required this.type,
  });

  ToyDriver createFake() {
    switch (type) {
      case 'vibrator':
        return FakeVibratorDriver(toyId: toyId, toyName: toyName);
      case 'ems':
        return FakeEMSDriver(toyId: toyId, toyName: toyName);
      case 'enema':
        return FakeEnemaDriver(toyId: toyId, toyName: toyName);
      case 'lock':
        return FakeLockDriver(toyId: toyId, toyName: toyName);
      default:
        throw ArgumentError('Unknown type: $type');
    }
  }
}

/// 玩具注册表 — 管理 ToyDriver 实例 + 执行日志
class ToyRegistry extends ChangeNotifier {
  /// 全局单例（蓝牙页面和执行页面共享）
  static final ToyRegistry _instance = ToyRegistry._();
  factory ToyRegistry() => _instance;
  ToyRegistry._();

  final Map<String, ToyDriver> _drivers = {};
  final Map<String, BleConnection> _bleConns = {};
  final List<DriverLogEntry> _logs = [];

  Map<String, ToyDriver> get drivers => Map.unmodifiable(_drivers);
  Map<String, BleConnection> get bleConnections =>
      Map.unmodifiable(_bleConns);
  int get count => _drivers.length;
  List<DriverLogEntry> get logs => List.unmodifiable(_logs);

  /// 注册单个驱动
  void register(String toyId, ToyDriver driver, {BleConnection? conn}) {
    _drivers[toyId] = driver;
    if (conn != null) _bleConns[toyId] = conn;
    driver.onLog = (entry) {
      _logs.add(entry);
      notifyListeners();
    };
    _addLog('STATUS', 'system', '✅ 已注册 $toyId (${driver.toyName})');
    notifyListeners();
  }

  /// 创建并注册真实 BLE 驱动
  ToyDriver registerBleDriver({
    required String toyId,
    required String toyName,
    required String type,
    required BleConnection conn,
  }) {
    ToyDriver driver;
    switch (type) {
      case 'vibrator':
        driver = VibratorDriver(toyId: toyId, toyName: toyName, conn: conn);
      case 'ems_v1':
        driver = EMSV1Driver(toyId: toyId, toyName: toyName, conn: conn);
      case 'ems_v2':
        driver = EMSV2Driver(toyId: toyId, toyName: toyName, conn: conn);
      case 'enema':
        driver = EnemaDriver(toyId: toyId, toyName: toyName, conn: conn);
      case 'lock':
        driver = LockDriver(toyId: toyId, toyName: toyName, conn: conn);
      default:
        throw ArgumentError('Unknown BLE driver type: $type');
    }
    register(toyId, driver, conn: conn);
    return driver;
  }

  /// 移除驱动（断开 BLE）
  Future<void> unregister(String toyId) async {
    final conn = _bleConns.remove(toyId);
    if (conn != null) {
      try {
        await conn.disconnect();
      } catch (_) {}
    }
    _drivers.remove(toyId);
    _addLog('STATUS', 'system', '❌ 已移除 $toyId');
    notifyListeners();
  }

  /// 批量注册假驱动
  void registerFakeDrivers(List<ToyConfig> configs) {
    for (final cfg in configs) {
      final driver = cfg.createFake();
      register(cfg.toyId, driver);
    }
  }

  /// 从 Lua 脚本中的玩具 ID 自动注册
  void registerFakeFromLua(String lua) {
    final ids = <String>{};
    for (final m in RegExp(r'(?:toy[._\\[])?(\\w+)(?:\\])?:').allMatches(lua)) {
      final id = m.group(1)!;
      if (id == 'wait' || id == 'print' || id == 'math') continue;
      ids.add(id);
    }
    for (final id in ids) {
      if (_drivers.containsKey(id)) continue;
      final driver = _guessDriver(id);
      if (driver != null) register(id, driver);
    }
  }

  ToyDriver? _guessDriver(String id) {
    final lower = id.toLowerCase();
    if (lower.contains('lock')) {
      return FakeLockDriver(toyId: id, toyName: id);
    }
    if (lower.contains('enema') || lower.contains('pump') || lower.contains('plug')) {
      return FakeEnemaDriver(toyId: id, toyName: id);
    }
    if (lower.contains('ems') || lower.contains('shock')) {
      return FakeEMSDriver(toyId: id, toyName: id);
    }
    if (lower.contains('mast') || lower.contains('vibe') || lower.contains('vibrator')
        || lower.contains('cup') || lower.contains('egg')) {
      return FakeVibratorDriver(toyId: id, toyName: id);
    }
    return FakeVibratorDriver(toyId: id, toyName: id);
  }

  /// 按 ID 查找
  ToyDriver? operator [](String toyId) => _drivers[toyId];

  /// 获取 BLE 连接
  BleConnection? getBleConnection(String toyId) => _bleConns[toyId];

  /// 能力快照
  List<Map<String, dynamic>> getCapabilitySnapshot() {
    return _drivers.entries.map((e) {
      return {'id': e.key, 'name': e.value.toyName, 'api': e.value.apiFunctions};
    }).toList();
  }

  /// 停止所有
  Future<void> stopAll() async {
    // 快照遍历，防止 concurrent modification
    final drivers = _drivers.values.toList();
    for (final d in drivers) {
      await d.emergencyStop();
    }
    _addLog('STATUS', 'system', '🛑 所有玩具已停止');
    notifyListeners();
  }

  /// 清除日志
  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  /// 完全清空
  Future<void> clear() async {
    for (final conn in _bleConns.values) {
      try { await conn.disconnect(); } catch (_) {}
    }
    _bleConns.clear();
    _drivers.clear();
    _logs.clear();
    notifyListeners();
  }

  /// 添加系统日志
  void logSystem(String level, String toyId, String message) {
    _addLog(level, toyId, message);
    notifyListeners();
  }

  void logError(String toyId, String message) {
    _addLog('ERROR', toyId, message);
    notifyListeners();
  }

  void _addLog(String level, String toyId, String message) {
    _logs.add(DriverLogEntry(
      timestamp: DateTime.now(),
      toyId: toyId,
      level: level,
      message: message,
    ));
  }
}
