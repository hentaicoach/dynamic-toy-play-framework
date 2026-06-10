import 'toy_driver.dart';
import '../ble_connection.dart';

// ═══════════════════════════════════════════════════════
// 飞机杯 / 跳蛋 · 真实 BLE 驱动
// YSKJ_TOY_BLE 通信协议 V1.1
// BLE FF40 · Service: 0000ff40 · Write: 0000ff41 · Notify: 0000ff42
// ═══════════════════════════════════════════════════════

class VibratorDriver extends ToyDriver {
  final BleConnection _conn;

  /// BLE 包校验和
  static int _checksum(List<int> bytes) =>
      bytes.fold(0, (sum, b) => (sum + b) & 0xFF);

  VibratorDriver({
    required super.toyId,
    required super.toyName,
    required BleConnection conn,
  }) : _conn = conn;

  @override
  Map<String, String> get apiFunctions => {
        'rate(motor_a, motor_b, motor_c)': '三马达力度 0-20',
        'set_mode(motor_select, mode_id)': '固定模式 (motor: 1=A,2=B,4=C, 7=ABC)',
        'stop()': '停止所有马达',
      };

  // ════════════════════════════════════════════
  // 0x10 查询设备信息
  // ════════════════════════════════════════════
  Future<void> queryDeviceInfo() async {
    final packet = _buildPacket([0x10]);
    await _conn.write(packet);
    logAction('query_device_info', []);
    logStatus('🔍 查询设备信息');
  }

  // ════════════════════════════════════════════
  // 0x11 固定模式控制
  // ════════════════════════════════════════════
  // 字节: 0x35, 0x11, motor_select, mode_id, checksum
  // motor_select: 0x01=A, 0x02=B, 0x04=C (可组合: 0x07=ABC)
  // mode_id: 0=关闭, 1-N=固定模式
  Future<void> setMode(int motorSelect, int modeId) async {
    final ms = motorSelect.clamp(0x01, 0x07);
    final md = modeId.clamp(0, 255);
    final packet = _buildPacket([0x11, ms, md]);
    await _conn.write(packet);
    logAction('set_mode', [motorSelect, modeId]);
    logStatus('🔢 模式 motor=$ms mode=$md');
  }

  // ════════════════════════════════════════════
  // 0x12 速率控制（三马达 0-20）
  // ════════════════════════════════════════════
  // 字节: 0x35, 0x12, mA(0-20), mB(0-20), mC(0-20), checksum
  // 注意：部分协议版本用 0-20，也有些用 0x00-0x14，兼容处理
  Future<void> rate(int motorA, int motorB, int motorC) async {
    final mA = motorA.clamp(0, 20);
    final mB = motorB.clamp(0, 20);
    final mC = motorC.clamp(0, 20);
    final packet = _buildPacket([0x12, mA, mB, mC]);
    await _conn.write(packet);
    logAction('rate', [mA, mB, mC]);
    logStatus('🌀 马达 $mA/$mB/$mC');
  }

  // ════════════════════════════════════════════
  // 停止 — 所有马达归零
  // ════════════════════════════════════════════
  Future<void> stop() async {
    await rate(0, 0, 0);
    logStatus('🛑 已停止');
  }

  @override
  Future<void> emergencyStop() async {
    await stop();
    logStatus('🚨 紧急停止');
  }

  @override
  Future<void> dispatchMethod(String method, List<dynamic> args) async {
    switch (method) {
      case 'rate':
        if (args.length >= 3) {
          await rate(_i(args[0]), _i(args[1]), _i(args[2]));
        }
      case 'set_intensity':
      case 'set_vibration':
        final v = _i(args.isNotEmpty ? args[0] : 0);
        await rate(v, v, v);
      case 'set_mode':
        if (args.length >= 2) {
          await setMode(_i(args[0]), _i(args[1]));
        }
      case 'stop':
        await stop();
    }
  }

  // ════════════════════════════════════════════
  // BLE 包构建
  // ════════════════════════════════════════════
  List<int> _buildPacket(List<int> data) {
    final packet = [0x35, ...data];
    packet.add(_checksum(packet));
    return packet;
  }

  int _i(dynamic v) =>
      v is int ? v : v is double ? v.round() : int.tryParse(v.toString()) ?? 0;
}
