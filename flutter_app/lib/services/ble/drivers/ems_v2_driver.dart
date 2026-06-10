import 'dart:typed_data';
import 'toy_driver.dart';
import '../ble_connection.dart';

// ═══════════════════════════════════════════════════════
// 电击器二代 · 真实 BLE 驱动
// YSKJ_EMS_BLE 通信协议 V2.0
// BLE FF30 · Service: 0000ff30 · Write: 0000ff31 · Notify: 0000ff32
//
// V2 相比 V1 新增实时模式(0x02)和频率模式(0x03)，通道控制包格式不同
// ═══════════════════════════════════════════════════════

class EMSV2Driver extends ToyDriver {
  final BleConnection _conn;

  static int _checksum(List<int> bytes) =>
      bytes.fold(0, (sum, b) => (sum + b) & 0xFF);

  EMSV2Driver({
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
        'set_channel_freq_pattern(channel, intensity, [(freq,pw), ...])':
            '频率模式, 最多100对 (freq, pw)',
        'set_motor(state)': '内置马达 0/1/0x11/0x12/0x13',
        'stop_all()': '停止所有通道',
      };

  // ════════════════════════════════════════════
  // 0x11 通道控制 — 固定模式 (mode=0x01)
  // ════════════════════════════════════════════
  // 10字节: 0x35, 0x11, 0x01, A_intensityH, A_intensityL, A_mode,
  //         B_intensityH, B_intensityL, B_mode, checksum
  // 强度: 0x0000=关闭, 0x0001-0x0114=开启(共276级)
  // 模式: 0x01-0x10 = 16种固定模式
  Future<void> setChannelFixed({
    int intensityA = 0,
    int modeA = 1,
    int intensityB = 0,
    int modeB = 1,
  }) async {
    final ia = intensityA.clamp(0, 276);
    final ib = intensityB.clamp(0, 276);
    final ma = modeA.clamp(0, 16);
    final mb = modeB.clamp(0, 16);

    final packet = _buildPacket([
      0x11,
      0x01, // 固定模式
      (ia >> 8) & 0xFF,
      ia & 0xFF,
      ma,
      (ib >> 8) & 0xFF,
      ib & 0xFF,
      mb,
    ]);
    await _conn.write(packet);
    logAction('set_channel_fixed', [ia, ma, ib, mb]);
    logStatus('⚡ A=${ia}/M$ma  B=${ib}/M$mb');
  }

  // ════════════════════════════════════════════
  // 0x11 通道控制 — 实时模式 (mode=0x02)
  // ════════════════════════════════════════════
  // 12字节: 0x35, 0x11, 0x02, A_intensityH, A_intensityL, A_freq, A_pw,
  //         B_intensityH, B_intensityL, B_freq, B_pw, checksum
  Future<void> setChannelRealtime({
    int intensityA = 0,
    int freqA = 30,
    int pwA = 50,
    int intensityB = 0,
    int freqB = 30,
    int pwB = 50,
  }) async {
    final ia = intensityA.clamp(0, 276);
    final ib = intensityB.clamp(0, 276);
    final fa = freqA.clamp(1, 100);
    final fb = freqB.clamp(1, 100);
    final pa = pwA.clamp(0, 100);
    final pb = pwB.clamp(0, 100);

    final packet = _buildPacket([
      0x11,
      0x02, // 实时模式
      (ia >> 8) & 0xFF,
      ia & 0xFF,
      fa,
      pa,
      (ib >> 8) & 0xFF,
      ib & 0xFF,
      fb,
      pb,
    ]);
    await _conn.write(packet);
    logAction('set_channel_realtime', [ia, fa, pa, ib, fb, pb]);
    logStatus('⚡ A=${ia}级 ${fa}Hz/${pa}us  B=${ib}级 ${fb}Hz/${pb}us');
  }

  // ════════════════════════════════════════════
  // 0x11 通道控制 — 频率模式 (mode=0x03)
  // ════════════════════════════════════════════
  // 可变长: 0x35, 0x11, 0x03, channel, intensityH, intensityL,
  //         [freq1, pw1, freq2, pw2, ...], checksum
  // 最多100对 (freq,pw)
  Future<void> setChannelFreqPattern({
    required String channel,
    required int intensity,
    required List<List<int>> pattern, // [[freq, pw], ...]
  }) async {
    final ch = channel.toUpperCase() == 'A' ? 0x01 : 0x02;
    final ci = intensity.clamp(0, 276);
    final pairs = pattern
        .take(100)
        .map((p) => [p[0].clamp(1, 100), p[1].clamp(0, 100)])
        .expand((p) => p)
        .toList();

    final packet = _buildPacket([
      0x11,
      0x03, // 频率模式
      ch,
      (ci >> 8) & 0xFF,
      ci & 0xFF,
      ...pairs,
    ]);
    await _conn.write(packet);
    logAction('set_channel_freq_pattern', [channel, ci, pairs.length]);
    logStatus('⚡ $channel 频率模式 ${ci}级 ${pairs.length~/2}步');
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
  // 0x13 计步功能
  // ════════════════════════════════════════════
  Future<void> setStepCounter(int state) async {
    final s = state.clamp(0, 4);
    final packet = _buildPacket([0x13, s]);
    await _conn.write(packet);
    logAction('set_step_counter', [s]);
  }

  // ════════════════════════════════════════════
  // 0x14 角度传感器
  // ════════════════════════════════════════════
  Future<void> setAngleSensor(int state) async {
    final s = state.clamp(0, 1);
    final packet = _buildPacket([0x14, s]);
    await _conn.write(packet);
    logAction('set_angle_sensor', [s]);
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
    final packet = _buildPacket([
      0x11, 0x01,
      0x00, 0x00, 0x00, // A intensity=0
      0x00, 0x00, 0x00, // B intensity=0
    ]);
    await _conn.write(packet);
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
        if (args.length >= 1) {
          // 兼容 V1 模式: channel, mode, intensity
          await setChannelFixed(intensityA: _i(args[0]), modeA: args.length > 1 ? _i(args[1]) : 1);
        }
      case 'set_channel_realtime':
        if (args.length >= 1) {
          await setChannelRealtime(intensityA: _i(args[0]));
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
}
