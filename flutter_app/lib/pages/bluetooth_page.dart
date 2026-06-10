import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/toy.dart';
import '../../providers/toy_state.dart';
import '../../providers/api_config.dart';
import '../services/ble/ble_manager.dart';
import '../services/ble/ble_connection.dart';
import '../services/ble/toy_registry.dart';
import '../services/ble/drivers/toy_driver.dart';
import '../services/ble/drivers/fake_drivers.dart';

class BluetoothPage extends StatefulWidget {
  final ToyRegistry? registry;

  const BluetoothPage({super.key, this.registry});

  @override
  State<BluetoothPage> createState() => _BluetoothPageState();
}

class _BluetoothPageState extends State<BluetoothPage> {
  // ── 真实 BLE 相关 ──
  final BleManager _bleManager = BleManager();
  StreamSubscription? _scanSub;
  StreamSubscription? _disconnectSub;
  bool _isInitialized = false;
  String? _errorMsg;

  // ── 通用 ──
  bool _isScanning = false;

  /// 扫描发现的设备（真实 BLE 用）
  final List<_FoundDevice> _foundDevices = [];

  /// 连接中的设备 ID
  final Set<String> _connectingIds = {};

  // ── Debug 模式的静态 mock 设备 ──
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
    if (!isDebug) {
      _initBle();
    }
  }

  Future<void> _initBle() async {
    try {
      await _bleManager.init();
      if (mounted) setState(() => _isInitialized = true);

      _disconnectSub = _bleManager.onDeviceDisconnected.listen((deviceId) {
        if (mounted) {
          context.read<ToyState>().removeToy(deviceId);
          widget.registry?.unregister(deviceId);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('设备 $deviceId 已断开')),
          );
        }
      });
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

  void _startScan() {
    if (_isScanning) return;
    final isDebug = context.read<ApiConfig>().debugMode;
    if (isDebug) {
      _startMockScan();
    } else {
      _startBleScan();
    }
  }

  void _startMockScan() {
    setState(() {
      _isScanning = true;
      _foundDevices.clear();
    });

    // 模拟 1.5 秒扫描延迟后展示 mock 设备
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      final existingIds = _foundDevices.map((d) => d.deviceId).toSet();
      for (final m in _mockDevices) {
        if (!existingIds.contains(m.id)) {
          _foundDevices.add(_FoundDevice(
            deviceId: m.id,
            deviceName: m.name,
            rssi: -60 - (m.id.hashCode % 30),
            serviceUuid: _mockServiceUuid(m.type),
          ));
        }
      }
      setState(() => _isScanning = false);
    });
  }

  void _startBleScan() {
    setState(() {
      _isScanning = true;
      _foundDevices.clear();
      _errorMsg = null;
    });

    _scanSub?.cancel();
    _scanSub = _bleManager.scanResults.listen((result) {
      if (!mounted) return;
      setState(() {
        final idx = _foundDevices.indexWhere((d) => d.deviceId == result.deviceId);
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

    _bleManager.startScan(timeout: const Duration(seconds: 10));
    Future.delayed(const Duration(seconds: 10), _stopScan);
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

  Future<void> _connect(String type, _FoundDevice device) async {
    if (_connectingIds.contains(device.deviceId)) return;
    setState(() => _connectingIds.add(device.deviceId));

    try {
      final isDebug = context.read<ApiConfig>().debugMode;

      if (isDebug) {
        // Debug: 用 FakeDriver
        final registry = widget.registry;
        if (registry != null) {
          registry.register(
            device.deviceId,
            _createFakeDriver(device.deviceId, device.deviceName, type),
          );
        }
      } else {
        // 真实 BLE 连接
        final conn = await _bleManager.connect(
          deviceId: device.deviceId,
          deviceName: device.deviceName,
          serviceUuid: device.serviceUuid,
        );
        widget.registry?.registerBleDriver(
          toyId: device.deviceId,
          toyName: device.deviceName,
          type: type,
          conn: conn,
        );
      }

      // 更新 ToyState
      final toy = Toy(
        id: device.deviceId,
        type: _toyTypeFromService(device.serviceUuid),
        name: device.deviceName,
        apiFunctions: _apiForService(device.serviceUuid),
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
          SnackBar(
            content: Text('❌ 连接失败: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _connectingIds.remove(device.deviceId));
    }
  }

  Future<void> _disconnectDevice(String deviceId) async {
    final isDebug = context.read<ApiConfig>().debugMode;
    if (!isDebug) {
      await _bleManager.disconnect(deviceId);
    }
    widget.registry?.unregister(deviceId);
    if (mounted) context.read<ToyState>().removeToy(deviceId);
  }

  Future<void> _disconnectAll() async {
    final ids = context.read<ToyState>().connectedToys.map((t) => t.id).toList();
    for (final id in ids) {
      await _disconnectDevice(id);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已断开所有设备')),
      );
    }
  }

  ToyDriver _createFakeDriver(String id, String name, String type) {
    switch (type) {
      case 'vibrator':
        return FakeVibratorDriver(toyId: id, toyName: name);
      case 'ems':
        return FakeEMSDriver(toyId: id, toyName: name);
      case 'enema':
        return FakeEnemaDriver(toyId: id, toyName: name);
      case 'lock':
        return FakeLockDriver(toyId: id, toyName: name);
      default:
        return FakeVibratorDriver(toyId: id, toyName: name);
    }
  }

  String _mockServiceUuid(String type) {
    switch (type) {
      case 'vibrator':
        return '0000ff40-0000-1000-8000-00805f9b34fb';
      case 'ems':
        return '0000ff30-0000-1000-8000-00805f9b34fb';
      case 'enema':
        return '0000ffb0-0000-1000-8000-00805f9b34fb';
      default:
        return '0000ff40-0000-1000-8000-00805f9b34fb';
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
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppTheme.primary,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _startScan,
              tooltip: '扫描',
            ),
        ],
      ),
      body: Column(
        children: [
          if (isDebug)
            _buildHintBanner(
              icon: Icons.bug_report,
              text: 'Debug 模式：点击即可模拟连接，使用 FakeDriver',
              color: AppTheme.warning,
            ),
          if (!isDebug && _errorMsg != null)
            _buildHintBanner(
              icon: Icons.error_outline,
              text: _errorMsg!,
              color: AppTheme.danger,
            ),
          if (!isDebug && !_isInitialized)
            _buildHintBanner(
              icon: Icons.bluetooth_disabled,
              text: '蓝牙未就绪，确保蓝牙已开启',
              color: AppTheme.textMuted,
            ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── 已连接设备 ──
                _buildSectionHeader(
                  '已连接',
                  connectedToys.isEmpty ? null : TextButton(
                    onPressed: _disconnectAll,
                    child: const Text('断开全部',
                        style: TextStyle(color: AppTheme.danger, fontSize: 12)),
                  ),
                ),
                const SizedBox(height: 4),

                if (connectedToys.isEmpty)
                  _buildEmptyState(
                    icon: Icons.bluetooth_disabled,
                    text: '暂无已连接设备',
                    subtext: '点击右上角扫描',
                  )
                else
                  ...connectedToys.map((toy) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _connectedDeviceCard(toy),
                  )),

                const SizedBox(height: 24),

                // ── 发现设备 ──
                _buildSectionHeader(
                  '发现设备',
                  _foundDevices.isNotEmpty
                      ? Text('${_foundDevices.length} 台',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted))
                      : null,
                ),
                const SizedBox(height: 4),

                if (_isScanning)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: const Column(
                      children: [
                        SizedBox(
                          width: 24, height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.primary),
                        ),
                        SizedBox(height: 12),
                        Text('正在扫描...',
                            style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
                      ],
                    ),
                  )
                else if (!_isScanning && _foundDevices.isNotEmpty)
                  ..._foundDevices.map((device) => _discoveredDeviceCard(
                    device, connectedToys,
                  ))
                else
                  _buildEmptyState(
                    icon: Icons.search,
                    text: '点击右上角开始扫描',
                    subtext: isDebug ? '将展示 4 台模拟设备' : '需要已开启蓝牙',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  // Widgets
  // ═══════════════════════════════════════════════

  Widget _buildHintBanner({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 10, color: color)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, Widget? trailing) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildEmptyState({required IconData icon, required String text, String? subtext}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: AppTheme.textMuted),
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          if (subtext != null) ...[
            const SizedBox(height: 4),
            Text(subtext, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          ],
        ],
      ),
    );
  }

  Widget _connectedDeviceCard(Toy toy) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.success.withOpacity(0.15),
          radius: 16,
          child: Text(toy.type.icon, style: const TextStyle(fontSize: 16)),
        ),
        title: Text(toy.name, style: const TextStyle(fontSize: 14)),
        subtitle: Text('已连接 · ${toy.type.displayName}',
            style: const TextStyle(fontSize: 11, color: AppTheme.success)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bluetooth_connected, size: 16, color: AppTheme.success),
            const SizedBox(width: 8),
            InkResponse(
              onTap: () => _disconnectDevice(toy.id),
              child: const Icon(Icons.close, color: AppTheme.textMuted, size: 20),
            ),
          ],
        ),
        onTap: () => _showToyDetail(context, toy),
      ),
    );
  }

  Widget _discoveredDeviceCard(_FoundDevice device, List<Toy> connectedToys) {
    final alreadyConnected = connectedToys.any((t) => t.id == device.deviceId);
    final isConnecting = _connectingIds.contains(device.deviceId);
    final toyType = _toyTypeFromService(device.serviceUuid);

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.bgSurface,
          radius: 16,
          child: Text(toyType.icon, style: const TextStyle(fontSize: 16)),
        ),
        title: Text(device.deviceName, style: const TextStyle(fontSize: 14)),
        subtitle: Row(
          children: [
            Text(device.deviceId,
                style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
            const SizedBox(width: 8),
            Text('${device.rssi} dBm',
                style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
            const SizedBox(width: 8),
            _rssiIndicator(device.rssi),
          ],
        ),
        trailing: alreadyConnected
            ? const Text('已连接',
                style: TextStyle(fontSize: 12, color: AppTheme.success))
            : isConnecting
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton(
                    onPressed: () => _connect(
                      _toyTypeFromService(device.serviceUuid).name,
                      device,
                    ),
                    child: const Text('连接'),
                  ),
      ),
    );
  }

  Widget _rssiIndicator(int rssi) {
    final bars = rssi > -50 ? 4 : rssi > -65 ? 3 : rssi > -80 ? 2 : 1;
    return Row(
      children: List.generate(4, (i) {
        return Container(
          width: 3,
          height: 4 + i * 3,
          margin: const EdgeInsets.only(right: 1),
          decoration: BoxDecoration(
            color: i < bars ? AppTheme.success : AppTheme.textMuted,
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }

  void _showToyDetail(BuildContext context, Toy toy) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(toy.type.icon, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(toy.name,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(toy.type.displayName,
                        style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text('支持指令',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            ...toy.apiFunctions.entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                        children: [
                          TextSpan(
                              text: e.key,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                          TextSpan(text: '  ${e.value}'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  _disconnectDevice(toy.id);
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.danger.withOpacity(0.1),
                ),
                child: const Text('断开连接', style: TextStyle(color: AppTheme.danger)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  // 辅助
  // ═══════════════════════════════════════════════

  ToyType _toyTypeFromService(String serviceUuid) {
    switch (serviceUuid.toLowerCase()) {
      case '0000ff40-0000-1000-8000-00805f9b34fb':
        return ToyType.masturbator;
      case '0000ff30-0000-1000-8000-00805f9b34fb':
        return ToyType.ems;
      case '0000ffb0-0000-1000-8000-00805f9b34fb':
        return ToyType.enema;
      default:
        return ToyType.unknown;
    }
  }

  Map<String, String> _apiForService(String serviceUuid) {
    switch (serviceUuid.toLowerCase()) {
      case '0000ff40-0000-1000-8000-00805f9b34fb':
        return {
          'rate(motor_a, motor_b, motor_c)': '三马达力度 0-20',
          'set_mode(motor_select, mode_id)': '固定模式',
          'stop()': '停止所有马达',
        };
      case '0000ff30-0000-1000-8000-00805f9b34fb':
        return {
          'set_channel_fixed(channel, mode_id, intensity)': '固定模式, 强度0-276',
          'set_channel_realtime(channel, intensity, frequency, pulse_width)':
              '自定义EMS, freq 1-100Hz, pw 0-100us',
          'set_motor(state)': '内置马达 0/1',
          'stop_all()': '停止所有通道',
        };
      case '0000ffb0-0000-1000-8000-00805f9b34fb':
        return {
          'fill(seconds)': '注水',
          'drain(seconds)': '排水',
          'pause()': '暂停',
          'read_pressure()': '读取压力值',
        };
      default:
        return {};
    }
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
    required this.serviceUuid,
  });
}

class _MockDevice {
  final String name;
  final String id;
  final String type;

  const _MockDevice({
    required this.name,
    required this.id,
    required this.type,
  });
}
