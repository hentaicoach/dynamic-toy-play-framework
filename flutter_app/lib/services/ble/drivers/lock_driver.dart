import 'toy_driver.dart';
import '../ble_connection.dart';

// ═══════════════════════════════════════════════════════
// 电子锁 · 真实 BLE 驱动
// 协议：通用简单继电器控制（或者可配 FF40 小功率马达）
// ═══════════════════════════════════════════════════════

class LockDriver extends ToyDriver {
  final BleConnection _conn;
  bool _isLocked = false;
  bool get isLocked => _isLocked;

  static int _checksum(List<int> bytes) =>
      bytes.fold(0, (sum, b) => (sum + b) & 0xFF);

  LockDriver({
    required super.toyId,
    required super.toyName,
    required BleConnection conn,
  }) : _conn = conn;

  @override
  Map<String, String> get apiFunctions => {
        'lock()': '上锁',
        'unlock()': '解锁',
      };

  /// 上锁 — 0x12 速率控制，正转锁定（模拟）
  Future<void> lock() async {
    final packet = _buildPacket([0x12, 10, 0, 0]); // A马达中速 2秒
    await _conn.write(packet);
    _isLocked = true;
    logAction('lock', []);
    logStatus('🔒 已上锁');
    // 延时后停止
    Future.delayed(const Duration(seconds: 2), () async {
      if (_isLocked) {
        final stopPacket = _buildPacket([0x12, 0, 0, 0]);
        await _conn.write(stopPacket);
      }
    });
  }

  /// 解锁 — 0x12 速率控制，反转解锁
  Future<void> unlock() async {
    final packet = _buildPacket([0x12, 0, 10, 0]); // B马达中速 2秒
    await _conn.write(packet);
    logAction('unlock', []);
    logStatus('🔓 已解锁');
    // 延时后停止
    Future.delayed(const Duration(seconds: 2), () async {
      if (!_isLocked) {
        final stopPacket = _buildPacket([0x12, 0, 0, 0]);
        await _conn.write(stopPacket);
      }
    });
  }

  @override
  Future<void> emergencyStop() async {
    _isLocked = false;
    final packet = _buildPacket([0x12, 0, 0, 0]);
    await _conn.write(packet);
    logAction('emergencyStop', []);
    logStatus('🚨 紧急停止，已解锁');
  }

  @override
  Future<void> dispatchMethod(String method, List<dynamic> args) async {
    switch (method) {
      case 'lock':
        await lock();
      case 'unlock':
        await unlock();
    }
  }

  List<int> _buildPacket(List<int> data) {
    final packet = [0x35, ...data];
    packet.add(_checksum(packet));
    return packet;
  }
}
