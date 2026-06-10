import 'dart:typed_data';
import 'toy_driver.dart';
import '../ble_connection.dart';

// ═══════════════════════════════════════════════════════
// 电击器一代 · 真实 BLE 驱动
// YSKJ_EMS_BLE 通信协议 V1.6
// BLE FF30 · Service: 0000ff30 · Write: 0000ff31 · Notify: 0000ff32
// ═══════════════════════════════════════════════════════

class EMSV1Driver extends ToyDriver {
  final BleConnection _conn;

  static int _checksum(List<int> bytes) =>
      bytes.fold(0, (sum, b) => (sum + b) & 0xFF);

  EMSV1Driver({
    required super.toyId,
    required super.toyName,
    required BleConnection conn,
  }) : _conn = conn;

  @override
  Map<String, String> get apiFunctions => {
        'set_channel_fixed(channel, mode_id, intensity)':
            '固定模式, intensity 0-276, mode 1-16',
        'set_channel_realtime(channel, intensity, frequency, pulse_width)':
            '自定义EMS, freq 1-100Hz, pw 0-100us',
        'set_motor(state)': '内置马达 0/1/0x11/0x12/0x13',
        'stop_all()': '停止所有通道',
      };

  // ════════════════════════════════════════════
  // 0x11 通道控制 — 固定模式
  // ════════════════════════════════════════════
  // 10字节: 0x35, 0x11, channel, on_off, intensityH, intensityL, mode,
  //         freq(固定模式0x00), pw(固定模式0x00), checksum
  Future<void> setChannelFixed(
      String channel, int modeId, int intensity) async {
    final ch = _channelByte(channel);
    final onOff = intensity > 0 ? 0x01 : 0x00;
    final ci = intensity.clamp(0, 276);
    final md = modeId.clamp(1, 16);
    final packet = _buildPacket([
      0x11,
      ch,
      onOff,
      (ci >> 8) & 0xFF, // intensity high byte
      ci & 0xFF, // intensity low byte
      md,
      0x00, // freq (固定模式写0)
      0x00, // pulse width (固定模式写0)
    ]);
    await _conn.write(packet);
    logAction('set_channel_fixed', [channel, modeId, ci]);
    logStatus('⚡ ${ch == 0x03 ? "AB" : (ch == 0x01 ? "A" : "B")} 模式$md 强度$ci/276');
  }

  // ════════════════════════════════════════════
  // 0x11 通道控制 — 自定义/实时模式
  // ════════════════════════════════════════════
  // 10字节: 0x35, 0x11, channel, on_off, intensityH, intensityL,
  //         0x11(自定义), freq(1-100Hz), pw(0-100us), checksum
  Future<void> setChannelRealtime(String channel, int intensity,
      int frequency, int pulseWidth) async {
    final ch = _channelByte(channel);
    final onOff = intensity > 0 ? 0x01 : 0x00;
    final ci = intensity.clamp(0, 276);
    final cf = frequency.clamp(1, 100);
    final cp = pulseWidth.clamp(0, 100);
    final packet = _buildPacket([
      0x11,
      ch,
      onOff,
      (ci >> 8) & 0xFF,
      ci & 0xFF,
      0x11, // 自定义模式标记
      cf,
      cp,
    ]);
    await _conn.write(packet);
    logAction('set_channel_realtime', [channel, ci, cf, cp]);
    logStatus('⚡ ${ch == 0x03 ? "AB" : (ch == 0x01 ? "A" : "B")} 实时 ${ci}级 ${cf}Hz ${cp}us');
  }

  // ════════════════════════════════════════════
  // 0x12 马达控制
  // ════════════════════════════════════════════
  Future<void> setMotor(int state) async {
    final s = state.clamp(0, 0x13);
    final packet = _buildPacket([0x12, s]);
    await _conn.write(packet);
    logAction('set_motor', [s]);
    logStatus('🔌 马达 ${_motorStateDesc(s)}');
  }

  // ════════════════════════════════════════════
  // 0x71 查询命令
  // ════════════════════════════════════════════
  Future<void> queryStatus(int queryType) async {
    final packet = _buildPacket([0x71, queryType]);
    await _conn.write(packet);
    logAction('query', [queryType]);
  }

  Future<void> queryChannelA() async => queryStatus(0x01);
  Future<void> queryChannelB() async => queryStatus(0x02);
  Future<void> queryMotor() async => queryStatus(0x03);
  Future<void> queryBattery() async => queryStatus(0x04);
  Future<void> queryStepData() async => queryStatus(0x05);
  Future<void> queryAngleData() async => queryStatus(0x06);

  // ════════════════════════════════════════════
  // 停止
  // ════════════════════════════════════════════
  Future<void> stopAll() async {
    // 发两路关闭指令
    final packetA = _buildPacket([0x11, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
    final packetB = _buildPacket([0x11, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
    await _conn.write(packetA);
    await _conn.write(packetB);
    logAction('stop_all', []);
    logStatus('🛑 所有通道已停止');
  }

  @override
  Future<void> emergencyStop() async {
    await stopAll();
    await setMotor(0);
    logStatus('🚨 紧急停止，所有通道断电');
  }

  @override
  Future<void> dispatchMethod(String method, List<dynamic> args) async {
    switch (method) {
      case 'set_channel_fixed':
        if (args.length >= 3) {
          await setChannelFixed(_s(args[0]), _i(args[1]), _i(args[2]));
        }
      case 'set_channel_realtime':
        if (args.length >= 4) {
          await setChannelRealtime(
              _s(args[0]), _i(args[1]), _i(args[2]), _i(args[3]));
        }
      case 'set_current':
        if (args.length >= 2) {
          await setChannelFixed('A', 1, _i(args[1]));
        }
      case 'set_motor':
        await setMotor(_i(args.isNotEmpty ? args[0] : 0));
      case 'stop':
      case 'stop_all':
        await stopAll();
    }
  }

  // ════════════════════════════════════════════
  // 辅助
  // ════════════════════════════════════════════

  int _channelByte(String channel) {
    switch (channel.toUpperCase()) {
      case 'A':
        return 0x01;
      case 'B':
        return 0x02;
      case 'AB':
      case 'BOTH':
        return 0x03;
      default:
        return 0x03; // 默认双通道
    }
  }

  List<int> _buildPacket(List<int> data) {
    final packet = [0x35, ...data];
    packet.add(_checksum(packet));
    return packet;
  }

  String _motorStateDesc(int s) {
    switch (s) {
      case 0: return '关闭';
      case 1: return '开启';
      case 0x11: return '预设频率1';
      case 0x12: return '预设频率2';
      case 0x13: return '预设频率3';
      default: return '状态$s';
    }
  }

  int _i(dynamic v) =>
      v is int ? v : v is double ? v.round() : int.tryParse(v.toString()) ?? 0;
  String _s(dynamic v) => v.toString();
}
