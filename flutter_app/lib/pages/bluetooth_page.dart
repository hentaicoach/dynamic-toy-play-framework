import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../config/theme.dart';
import '../../models/toy.dart';
import '../../providers/toy_state.dart';
import '../../providers/api_config.dart';
import '../services/ble/ble_manager.dart';
import '../services/ble/ble_connection.dart';
import '../services/ble/toy_registry.dart';
import '../services/ble/drivers/toy_driver.dart';
import '../services/ble/drivers/fake_drivers.dart';
import '../services/ble/native_ble_scanner.dart';
import 'package:yokonex_play/config/constants.dart';

class BluetoothPage extends StatefulWidget {
  final ToyRegistry? registry;

  const BluetoothPage({super.key, this.registry});

  @override
  State<BluetoothPage> createState() => _BluetoothPageState();
}

class _BluetoothPageState extends State<BluetoothPage> {
  final BleManager _bleManager = BleManager();
  StreamSubscription? _scanSub;
  StreamSubscription? _disconnectSub;
  bool _isScanning = false;
  bool _isInitialized = false;
  String? _errorMsg;

  final List<_FoundDevice> _foundDevices = [];
  final Set<String> _connectingIds = {};
  String? _expandedToyId;

  static final List<_MockDevice> _mockDevices = [
    _MockDevice(name: '蛋蛋-01', id: 'egg_1', type: 'vibrator'),
    _MockDevice(name: '飞机杯-M2', id: 'mast_1', type: 'vibrator'),
    _MockDevice(name: '电击器-EMS4', id: 'ems_1', type: 'ems'),
    _MockDevice(name: '灌肠器-P3', id: 'enema_1', type: 'enema'),
  ];

  @override
  void initState() {
    super.initState();
    final isDebug = context.read<ApiConfig>().debugMode;
    if (!isDebug) _initBle();
  }

  Future<void> _initBle() async {
    try {
      await _bleManager.init();
      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      if (mounted) setState(() => _errorMsg = 'BLE 初始化失败: $e');
    }
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _disconnectSub?.cancel();
    _bleManager.stopScan();
    super.dispose();
  }

  // ═══════════════════════════════════════════════
  // 扫描
  // ═══════════════════════════════════════════════

  Future<void> _startScan() async {
    if (_isScanning) return;
    final isDebug = context.read<ApiConfig>().debugMode;
    if (isDebug) {
      _startMockScan();
    } else {
      await _startBleScan();
    }
  }

  void _startMockScan() {
    setState(() { _isScanning = true; _foundDevices.clear(); });
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      final existingIds = _foundDevices.map((d) => d.deviceId).toSet();
      for (final m in _mockDevices) {
        if (!existingIds.contains(m.id)) {
          _foundDevices.add(_FoundDevice(
            deviceId: m.id, deviceName: m.name,
            rssi: -60 - (m.id.hashCode % 30),
          ));
        }
      }
      setState(() => _isScanning = false);
    });
  }

  Future<void> _startBleScan() async {
    try {
      Log.i('[BLE] 启动 flutter_blue_plus 扫描...');
      setState(() { _isScanning = true; _foundDevices.clear(); _errorMsg = null; });

      // 检查定位服务是否开启（Android BLE 扫描需要）
      final nativeScanner = NativeBleScanner();
      if (!await nativeScanner.isLocationEnabled()) {
        if (mounted) {
          _showLocationRequiredDialog();
        }
        setState(() => _isScanning = false);
        return;
      }

      // 请求定位权限（Android 12+ 部分 OEM 需要显式申请）
      Log.i('[BLE] 请求定位权限...');
      final locGranted = await nativeScanner.requestLocationPermission();
      Log.i('[BLE] 定位权限结果: $locGranted');
      if (!locGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('需要定位权限才能扫描 BLE 设备，请手动在系统设置中开启'),
              backgroundColor: AppTheme.warning,
              duration: Duration(seconds: 4),
            ),
          );
        }
        setState(() => _isScanning = false);
        return;
      }

      // 确保 BLE 已初始化
      if (!_isInitialized) {
        await _bleManager.init();
        if (mounted) setState(() => _isInitialized = true);
      }

      // 检查蓝牙是否可用
      final adapterState = _bleManager.adapterState;
      if (adapterState != BluetoothAdapterState.on) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('蓝牙未开启 (${adapterState.name})'),
              backgroundColor: AppTheme.warning,
            ),
          );
        }
        setState(() => _isScanning = false);
        return;
      }

      // 订阅扫描结果流
      _scanSub?.cancel();
      _scanSub = _bleManager.scanResults.listen((result) {
        Log.i('[BLE] 发现:  ${result.deviceName} (${result.deviceId}) RSSI=${result.rssi} UUID=${result.serviceUuid}');
        if (!mounted) return;
        setState(() {
          final idx = _foundDevices.indexWhere((fd) => fd.deviceId == result.deviceId);
          if (idx >= 0) {
            _foundDevices[idx] = _FoundDevice(
              deviceId: result.deviceId,
              deviceName: result.deviceName,
              rssi: result.rssi,
              serviceUuid: result.serviceUuid,
            );
          } else {
            _foundDevices.add(_FoundDevice(
              deviceId: result.deviceId,
              deviceName: result.deviceName,
              rssi: result.rssi,
              serviceUuid: result.serviceUuid,
            ));
          }
        });
      });

      // 启动扫描，10 秒超时（startScan 立即返回，扫描在后台运行）
      await _bleManager.startScan(timeout: const Duration(seconds: 10));

      // 等待扫描自动超时结束（通过 isScanning 流检测）
      Log.i('[BLE] 扫描中...');
      await FlutterBluePlus.isScanning.firstWhere((s) => s == false);
      Log.i('[BLE] 扫描完成');

      // 取消订阅流
      await _scanSub?.cancel();
      _scanSub = null;

      Log.i('[BLE] 扫描完成，共发现 ${_foundDevices.length} 个设备');

      if (mounted) setState(() => _isScanning = false);

      if (_foundDevices.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('扫描完成，未发现设备。请确保：\n1. 手机定位服务已开启\n2. 玩具已开机并靠近手机'),
            backgroundColor: AppTheme.textMuted,
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      Log.w('[BLE] 扫描异常: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('蓝牙异常: $e'), backgroundColor: AppTheme.danger),
        );
      }
      setState(() => _isScanning = false);
    }
  }

  /// 提示用户开启定位服务（Android BLE 扫描必需）
  void _showLocationRequiredDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Row(children: [
          Icon(Icons.location_on, color: AppTheme.warning, size: 20),
          SizedBox(width: 8),
          Text('需要开启定位', style: TextStyle(fontSize: 16)),
        ]),
        content: const Text(
          'Android 系统需要开启定位服务才能扫描到 BLE 蓝牙设备。\n\n'
          '请下拉通知栏 → 开启「位置信息」开关，然后重试扫描。\n\n'
          '（注：位置信息仅用于 BLE 扫描，位置数据不会离开手机）',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了', style: TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
  }

  void _stopScan() {
    _bleManager.stopScan();
    _scanSub?.cancel();
    _scanSub = null;
    if (mounted) setState(() => _isScanning = false);
  }

  // ═══════════════════════════════════════════════
  // 连接 / 断开
  // ═══════════════════════════════════════════════

  Future<void> _connect(String deviceName, String serviceUuid, _FoundDevice device) async {
    if (_connectingIds.contains(device.deviceId)) return;
    setState(() => _connectingIds.add(device.deviceId));

    try {
      final isDebug = context.read<ApiConfig>().debugMode;

      // 从 Service UUID 推断玩具类型
      final type = _typeFromServiceUuid(serviceUuid);
      Log.i('[BLE] 连接: ${device.deviceName} uuid=$serviceUuid type=$type');

      if (isDebug) {
        final driver = _createFakeDriver(device.deviceId, device.deviceName, type);
        widget.registry?.register(device.deviceId, driver);
        // Debug 模式也注册短名
        final shortName = _shortToyName(device.deviceName, type);
        if (shortName != null) {
          widget.registry?.register(shortName, driver);
        }
      } else {
        final conn = await _bleManager.connect(
          deviceId: device.deviceId,
          deviceName: device.deviceName,
          serviceUuid: serviceUuid,
        );
        final driver = widget.registry?.registerBleDriver(
          toyId: device.deviceId,
          toyName: device.deviceName,
          type: type,
          conn: conn,
        );
        // 同时注册短名别名（如 enema_1, mast_1），方便 playbook 按名字调用
        final shortName = _shortToyName(device.deviceName, type);
        if (shortName != null && driver != null) {
          widget.registry?.register(shortName, driver, conn: conn);
        }
      }

      final toy = Toy(
        id: device.deviceId,
        type: _guessToyType(device.deviceName, serviceUuid),
        name: device.deviceName,
        apiFunctions: _apiForType(type),
      );
      if (mounted) {
        context.read<ToyState>().addToy(toy);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ 已连接 ${device.deviceName}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 连接失败: $e'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _connectingIds.remove(device.deviceId));
    }
  }

  Future<void> _disconnectDevice(String deviceId) async {
    await _bleManager.disconnect(deviceId);
    widget.registry?.unregister(deviceId);
    if (mounted) context.read<ToyState>().removeToy(deviceId);
  }

  Future<void> _disconnectAll() async {
    final ids = context.read<ToyState>().connectedToys.map((t) => t.id).toList();
    for (final id in ids) { await _disconnectDevice(id); }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已断开所有设备')),
      );
    }
  }

  String _guessServiceUuid(String type) {
    switch (type) {
      case 'vibrator': return '0000ff40-0000-1000-8000-00805f9b34fb';
      case 'ems': return '0000ff30-0000-1000-8000-00805f9b34fb';
      case 'enema': return '0000ffb0-0000-1000-8000-00805f9b34fb';
      default: return '0000ff40-0000-1000-8000-00805f9b34fb';
    }
  }

  ToyType _guessToyType(String name, String serviceUuid) {
    // 1. 优先用广播的 Service UUID 判断
    if (serviceUuid.isNotEmpty) {
      final uuidLower = serviceUuid.toLowerCase();
      if (uuidLower.contains('ffb0')) return ToyType.enema;
      if (uuidLower.contains('ff30')) return ToyType.ems;
      if (uuidLower.contains('ff40')) return ToyType.masturbator;
    }

    // 2. 用设备名匹配
    final lower = name.toLowerCase();
    if (lower.contains('ems') || lower.contains('shock')) return ToyType.ems;
    if (lower.contains('enema') || lower.contains('pump')) return ToyType.enema;
    if (lower.contains('lock')) return ToyType.lock;
    if (lower.contains('fjb') || lower.contains('蛋') || lower.contains('杯')
        || lower.contains('vibe') || lower.contains('mast') || lower.contains('egg')
        || lower.contains('飞机')) return ToyType.masturbator;
    return ToyType.unknown;
  }

  /// 从 Service UUID 推断玩具类型字符串（用于 API 选择）
  String _typeFromServiceUuid(String uuid) {
    final u = uuid.toLowerCase();
    if (u.contains('ffb0')) return 'enema';
    if (u.contains('ff30')) return 'ems';
    if (u.contains('ff40')) return 'vibrator';
    return 'vibrator'; // 默认当成 FF40 马达设备
  }

  /// 生成短名别名（用于 playbook 里的玩具 ID）
  String? _shortToyName(String deviceName, String type) {
    final lower = deviceName.toLowerCase();
    // 已知设备名直接生成
    if (lower.contains('yiskj') || type == 'enema') return 'enema_1';
    if (lower.contains('ycy') || lower.contains('fjb') || type == 'vibrator') return 'mast_1';
    if (type == 'ems') return 'ems_1';
    if (type == 'lock') return 'lock_1';
    return null;
  }

  Map<String, String> _apiForType(String type) {
    switch (type) {
      case 'vibrator': return {
        'rate(motor_a, motor_b, motor_c)': '三马达力度 0-20',
        'stop()': '停止所有马达',
      };
      case 'ems': return {
        'set_channel_fixed(channel, mode_id, intensity)': '固定模式, 强度0-276',
        'stop_all()': '停止所有通道',
      };
      case 'enema': return {
        'fill(seconds)': '注水', 'drain(seconds)': '排水',
        'pause()': '暂停', 'read_pressure()': '读取压力值',
      };
      case 'lock': return {'lock()': '上锁', 'unlock()': '解锁'};
      default: return {};
    }
  }

  ToyDriver _createFakeDriver(String id, String name, String type) {
    switch (type) {
      case 'vibrator': return FakeVibratorDriver(toyId: id, toyName: name);
      case 'ems': return FakeEMSDriver(toyId: id, toyName: name);
      case 'enema': return FakeEnemaDriver(toyId: id, toyName: name);
      case 'lock': return FakeLockDriver(toyId: id, toyName: name);
      default: return FakeVibratorDriver(toyId: id, toyName: name);
    }
  }

  // ── 功能测试按钮 ──

  Future<void> _callTestFunction(ToyDriver driver, String method, String toyId, ToyType type) async {
    List<dynamic> testArgs;
    switch (method) {
      case 'rate': testArgs = [10, 5, 10];
      case 'set_mode': testArgs = [7, 1];
      case 'stop': testArgs = [];
      case 'set_channel_fixed': testArgs = ['A', 3, 100];
      case 'set_channel_realtime': testArgs = ['A', 120, 50, 50];
      case 'set_motor': testArgs = [1];
      case 'stop_all': testArgs = [];
      case 'fill': testArgs = [3];
      case 'drain': testArgs = [3];
      case 'pause': testArgs = [];
      case 'read_pressure': testArgs = [];
      case 'lock': testArgs = [];
      case 'unlock': testArgs = [];
      default: testArgs = [];
    }
    try {
      await driver.callMethod(method, testArgs);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ $toyId.$method(${testArgs.join(',')})'), duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ $method: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final toyState = context.watch<ToyState>();
    final connectedToys = toyState.connectedToys;
    final apiConfig = context.watch<ApiConfig>();
    final isDebug = apiConfig.debugMode;

    return Scaffold(
      appBar: AppBar(
        title: const Text('蓝牙'),
        actions: [
          if (_isScanning)
            const Padding(padding: EdgeInsets.only(right: 16),
              child: SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)))
          else
            IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _startScan, tooltip: '扫描'),
        ],
      ),
      body: Column(
        children: [
          if (isDebug)
            _buildHintBanner(icon: Icons.bug_report, text: 'Debug 模式：点击即可模拟连接', color: AppTheme.warning),
          if (!isDebug && _errorMsg != null)
            _buildHintBanner(icon: Icons.error_outline, text: _errorMsg!, color: AppTheme.danger),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSectionHeader('已连接',
                  connectedToys.isEmpty ? null : TextButton(
                    onPressed: _disconnectAll,
                    child: const Text('断开全部', style: TextStyle(color: AppTheme.danger, fontSize: 12)),
                  ),
                ),
                const SizedBox(height: 4),
                if (connectedToys.isEmpty)
                  _buildEmptyState(icon: Icons.bluetooth_disabled, text: '暂无已连接设备', subtext: '点击右上角扫描')
                else
                  ...connectedToys.map((toy) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _connectedDeviceCard(toy),
                  )),
                const SizedBox(height: 24),
                _buildSectionHeader('发现设备', null),
                const SizedBox(height: 4),
                if (_isScanning)
                  Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 20),
                    child: const Column(children: [
                      SizedBox(width: 24, height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)),
                      SizedBox(height: 12),
                      Text('正在扫描...', style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
                    ]))
                else if (!_isScanning && _foundDevices.isNotEmpty)
                  ..._foundDevices.map((device) => _discoveredDeviceCard(device, connectedToys))
                else
                  _buildEmptyState(icon: Icons.search, text: '点击右上角开始扫描',
                      subtext: isDebug ? '将展示 4 台模拟设备' : '需要已开启蓝牙'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Widgets ──

  Widget _buildHintBanner({required IconData icon, required String text, required Color color}) {
    return Container(width: double.infinity, margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3))),
      child: Row(children: [
        Icon(icon, size: 14, color: color), const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(fontSize: 10, color: color))),
      ]),
    );
  }

  Widget _buildSectionHeader(String title, Widget? trailing) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      if (trailing != null) trailing,
    ]);
  }

  Widget _buildEmptyState({required IconData icon, required String text, String? subtext}) {
    return Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Icon(icon, size: 36, color: AppTheme.textMuted), const SizedBox(height: 8),
        Text(text, style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
        if (subtext != null) ...[const SizedBox(height: 4), Text(subtext, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted))],
      ]),
    );
  }

  Widget _connectedDeviceCard(Toy toy) {
    final isExpanded = _expandedToyId == toy.id;
    final driver = widget.registry?[toy.id];

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Column(children: [
        InkWell(
          onTap: () => setState(() => _expandedToyId = isExpanded ? null : toy.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              CircleAvatar(backgroundColor: AppTheme.success.withOpacity(0.15), radius: 16,
                child: Text(toy.type.icon, style: const TextStyle(fontSize: 16))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(toy.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                Text('已连接 · ${toy.type.displayName}', style: const TextStyle(fontSize: 11, color: AppTheme.success)),
              ])),
              Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: AppTheme.textMuted, size: 20),
              const SizedBox(width: 4),
              InkResponse(onTap: () => _disconnectDevice(toy.id),
                child: const Icon(Icons.close, color: AppTheme.textMuted, size: 20)),
            ]),
          ),
        ),
        if (isExpanded && driver != null) ...[
          const Divider(height: 1, indent: 12, endIndent: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('🧪 功能测试', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6,
                children: toy.apiFunctions.entries.map((entry) {
                  final methodName = entry.key.split('(').first;
                  return ActionChip(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: AppTheme.primary.withOpacity(0.1),
                    side: BorderSide.none,
                    label: Text(methodName, style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
                    onPressed: () => _callTestFunction(driver, methodName, toy.id, toy.type),
                  );
                }).toList(),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _discoveredDeviceCard(_FoundDevice device, List<Toy> connectedToys) {
    final alreadyConnected = connectedToys.any((t) => t.id == device.deviceId);
    final isConnecting = _connectingIds.contains(device.deviceId);
    final toyType = _guessToyType(device.deviceName, device.serviceUuid);

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: AppTheme.bgSurface, radius: 16,
          child: Text(toyType.icon, style: const TextStyle(fontSize: 16))),
        title: Text(device.deviceName, style: const TextStyle(fontSize: 14)),
        subtitle: Row(children: [
          Text(device.deviceId, style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
          const SizedBox(width: 8),
          Text('${device.rssi} dBm', style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
        ]),
        trailing: alreadyConnected
            ? const Text('已连接', style: TextStyle(fontSize: 12, color: AppTheme.success))
            : isConnecting
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : TextButton(
                    onPressed: () => _connect(device.deviceName, device.serviceUuid, device),
                    child: const Text('连接'),
                  ),
      ),
    );
  }
}

class _FoundDevice {
  final String deviceId;
  final String deviceName;
  final int rssi;
  final String serviceUuid;
  const _FoundDevice({
    required this.deviceId,
    required this.deviceName,
    required this.rssi,
    this.serviceUuid = '',
  });
}

class _MockDevice {
  final String name;
  final String id;
  final String type;
  const _MockDevice({required this.name, required this.id, required this.type});
}
