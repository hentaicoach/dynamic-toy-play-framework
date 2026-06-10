import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'toy_driver.dart';
import '../ble_connection.dart';

// ═══════════════════════════════════════════════════════
// 灌肠机 · 真实 BLE 驱动
// TDL_YISKJ-003 协议规范 V1.0
// BLE FFB0 · Service: 0000ffb0 · Write: 0000ffb1 · Notify: 0000ffb2
// 通信：AES-128-ECB 加密，16字节包
// ═══════════════════════════════════════════════════════

class EnemaDriver extends ToyDriver {
  final BleConnection _conn;
  final Random _random = Random();

  /// AES-128-ECB 密钥（固定）
  static final encrypt.Key _aesKey = encrypt.Key(Uint8List.fromList([
    0xF6, 0x38, 0xBC, 0x9C, 0xFA, 0x47, 0x74, 0x80,
    0xAB, 0x32, 0x42, 0xF6, 0xB0, 0x45, 0x57, 0xA1,
  ]));

  late final encrypt.Encrypter _encrypter;

  /// 明文包头
  static const int _header1 = 0xBF;
  static const int _header2 = 0x0F;
  static const int _header3 = 0xA0; // 主机→设备指令
  static const int _headerResp = 0xB0; // 设备→主机响应

  /// 命令字节
  static const int _cmdFill = 0x01;    // 控制蠕动泵（注水）
  static const int _cmdDrain = 0x02;   // 控制抽水泵（排水）
  static const int _cmdPause = 0x03;   // 暂停所有泵
  static const int _cmdQuery = 0x04;   // 查询工作状态
  static const int _cmdBattery = 0x05; // 获取电量

  EnemaDriver({
    required super.toyId,
    required super.toyName,
    required BleConnection conn,
  }) : _conn = conn {
    _encrypter = encrypt.Encrypter(
      encrypt.AES(_aesKey, mode: encrypt.AESMode.ecb),
    );

    // 监听通知，解析压力上报
    _conn.notifications.listen(_handleNotification);
  }

  @override
  Map<String, String> get apiFunctions => {
        'fill(seconds)': '注水，时间秒',
        'drain(seconds)': '排水，时间秒',
        'pause()': '暂停所有泵',
        'read_pressure()': '读取压力值 (A, B)',
        'get_battery()': '获取电量',
      };

  // ════════════════════════════════════════════
  // AES-128-ECB 加密/解密
  // ════════════════════════════════════════════

  /// 加密明文包并发送
  Future<void> _sendEncrypted(Uint8List plain) async {
    final encrypted = _encrypter.encryptBytes(plain);
    await _conn.write(encrypted.bytes);
  }

  /// 解密密文包
  Uint8List _decrypt(List<int> cipherBytes) {
    final encrypted = encrypt.Encrypted(Uint8List.fromList(cipherBytes));
    return Uint8List.fromList(_encrypter.decryptBytes(encrypted));
  }

  /// 构建 16 字节明文包
  /// [BF, 0F, A0, cmd, data..., padding]
  Uint8List _buildPlainPacket(int cmd, [List<int> data = const []]) {
    final packet = List<int>.filled(16, 0);
    packet[0] = _header1;
    packet[1] = _header2;
    packet[2] = _header3;
    packet[3] = cmd;
    // 数据
    for (int i = 0; i < data.length && i < 12; i++) {
      packet[4 + i] = data[i];
    }
    // 剩余填充随机数
    for (int i = 4 + data.length; i < 16; i++) {
      packet[i] = _random.nextInt(256);
    }
    return Uint8List.fromList(packet);
  }

  // ════════════════════════════════════════════
  // 命令实现
  // ════════════════════════════════════════════

  /// 注水（蠕动泵正转）
  /// BF 0F A0 01 [status:00/01/02] [time:2字节,秒] [padding]
  Future<void> fill(int seconds) async {
    final timeBytes = _toUint16(seconds.clamp(0, 0xFFFF));
    final plain = _buildPlainPacket(_cmdFill, [
      0x01, // 正转
      timeBytes[0], timeBytes[1],
    ]);
    await _sendEncrypted(plain);
    logAction('fill', [seconds]);
    logStatus('💧 注水 ${seconds}s');
  }

  /// 排水（抽水泵正转）
  /// BF 0F A0 02 [status:00/01] [time:2字节,秒] [padding]
  Future<void> drain(int seconds) async {
    final timeBytes = _toUint16(seconds.clamp(0, 0xFFFF));
    final plain = _buildPlainPacket(_cmdDrain, [
      0x01, // 正转
      timeBytes[0], timeBytes[1],
    ]);
    await _sendEncrypted(plain);
    logAction('drain', [seconds]);
    logStatus('💧 排水 ${seconds}s');
  }

  /// 暂停所有泵
  Future<void> pause() async {
    final plain = _buildPlainPacket(_cmdPause);
    await _sendEncrypted(plain);
    logAction('pause', []);
    logStatus('⏸️ 泵已暂停');
  }

  /// 查询工作状态
  Future<Map<String, dynamic>> queryStatus() async {
    final plain = _buildPlainPacket(_cmdQuery);
    await _sendEncrypted(plain);
    logAction('query_status', []);
    // 注意：查询结果通过 notify 异步返回，需要等响应
    // 这里为简化，直接返回空，实际结果在 _handleNotification 里
    return {};
  }

  /// 读取压力值（从 notify 缓存读取）
  int _lastPressureA = 50;
  int _lastPressureB = 50;
  int _lastBattery = 85;

  int readPressureA() => _lastPressureA;
  int readPressureB() => _lastPressureB;

  @override
  Future<int> getBattery() async {
    // 覆盖父类的 getBattery，发 BLE 命令查询
    final plain = _buildPlainPacket(_cmdBattery);
    await _sendEncrypted(plain);
    logAction('get_battery', []);
    logStatus('🔋 查询电量');
    // 电量通过 notify 异步回调，这里直接返回缓存值
    // 真实的异步回调流程需要更复杂的等待机制
    return _lastBattery;
  }

  /// 压力读取（有返回值，被 callMethodWithResult 调用）
  Future<Map<String, int>> readPressure() async {
    logAction('read_pressure', []);
    logStatus('📊 压力 A=$_lastPressureA  B=$_lastPressureB');
    return {
      'pressure_a': _lastPressureA,
      'pressure_b': _lastPressureB,
    };
  }

  // ════════════════════════════════════════════
  // Notify 响应处理
  // ════════════════════════════════════════════

  void _handleNotification(List<int> data) {
    try {
      final plain = _decrypt(data);
      if (plain.length < 4) return;
      if (plain[0] != _header1 || plain[1] != _header2) return;
      if (plain[2] != _headerResp) return;

      final respCmd = plain[3];
      switch (respCmd) {
        case 0x01: // 工作状态上报
          final peristalticStatus = plain[4]; // 蠕动泵: 00=停止 01=正转 02=反转
          final suctionStatus = plain[5]; // 抽水泵: 00=停止 01=正转
          logStatus('📋 泵状态 蠕动泵=${_pumpStatusText(peristalticStatus)} 抽水泵=${_pumpStatusText(suctionStatus)}');
          break;
        case 0x02: // 压力上报
          _lastPressureA = (plain[4] << 8) | plain[5];
          _lastPressureB = (plain[6] << 8) | plain[7];
          logStatus('📊 压力上报 A=$_lastPressureA  B=$_lastPressureB');
          break;
        case 0x03: // 电量上报
          _lastBattery = plain[4];
          logStatus('🔋 电量 $_lastBattery%');
          break;
      }
    } catch (e) {
      logError('解析通知失败: $e');
    }
  }

  // ════════════════════════════════════════════
  // 紧急停止
  // ════════════════════════════════════════════
  @override
  Future<void> emergencyStop() async {
    await pause();
    logStatus('🚨 紧急停止');
  }

  @override
  Future<void> dispatchMethod(String method, List<dynamic> args) async {
    switch (method) {
      case 'fill':
        await fill(_i(args.isNotEmpty ? args[0] : 0));
      case 'drain':
        await drain(_i(args.isNotEmpty ? args[0] : 0));
      case 'pause':
      case 'stop':
        await pause();
      case 'read_pressure':
        await readPressure();
    }
  }

  @override
  Future<dynamic> callMethodWithResult(
      String method, List<dynamic> args) async {
    if (method == 'read_pressure') return readPressure();
    await callMethod(method, args);
    return 0;
  }

  // ════════════════════════════════════════════
  // 辅助
  // ════════════════════════════════════════════

  List<int> _toUint16(int value) => [(value >> 8) & 0xFF, value & 0xFF];

  String _pumpStatusText(int s) {
    switch (s) {
      case 0: return '停止';
      case 1: return '正转';
      case 2: return '反转';
      default: return '未知($s)';
    }
  }

  int _i(dynamic v) =>
      v is int ? v : v is double ? v.round() : int.tryParse(v.toString()) ?? 0;
}
