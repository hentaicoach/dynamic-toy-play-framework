import 'toy_driver.dart';

// ═════════════════════════════════════════════
// 飞机杯 / 跳蛋 · FakeDriver
// BLE FF40 · 三马达 0-20 + 固定模式
// ═════════════════════════════════════════════

class FakeVibratorDriver extends ToyDriver {
  FakeVibratorDriver({required super.toyId, super.toyName = '飞机杯'});

  @override
  Map<String, String> get apiFunctions => {
        'rate(motor_a, motor_b, motor_c)': '三马达力度 0-20',
        'set_mode(motor_select, mode_id)': '固定模式',
        'stop()': '停止所有马达',
      };

  Future<void> rate(int motorA, int motorB, int motorC) async {
    final mA = motorA.clamp(0, 20);
    final mB = motorB.clamp(0, 20);
    final mC = motorC.clamp(0, 20);
    logAction('rate', [mA, mB, mC]);
    logStatus('🌀 马达 $mA/$mB/$mC');
  }

  Future<void> setMode(int motorSelect, int modeId) async {
    logAction('set_mode', [motorSelect, modeId]);
    logStatus('🔢 模式 motor=$motorSelect mode=$modeId');
  }

  Future<void> stop() async {
    logAction('stop', []);
    logStatus('🛑 已停止');
  }

  @override
  Future<void> emergencyStop() async {
    logAction('emergencyStop', []);
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
        // AI 有时生成 set_intensity(value) 或 set_vibration(value)
        final v = _i(args.isNotEmpty ? args[0] : 0);
        await rate(v, v, v);
      case 'set_mode':
        if (args.length >= 2) await setMode(_i(args[0]), _i(args[1]));
      case 'stop':
        await stop();
    }
  }

  int _i(dynamic v) =>
      v is int ? v : v is double ? v.round() : int.tryParse(v.toString()) ?? 0;
}

// ═════════════════════════════════════════════
// 电击器 · FakeDriver
// BLE FF30 · 2通道 276级 + 16模式 + 频率/脉宽
// ═════════════════════════════════════════════

class FakeEMSDriver extends ToyDriver {
  FakeEMSDriver({required super.toyId, super.toyName = '电击器'});

  @override
  Map<String, String> get apiFunctions => {
        'set_channel_fixed(channel, mode_id, intensity)':
            '固定模式, 强度0-276',
        'set_channel_realtime(channel, intensity, frequency, pulse_width)':
            '自定义EMS, freq 1-100Hz, pw 0-100us',
        'set_motor(state)': '内置马达 0/1',
        'stop_all()': '停止所有通道',
      };

  Future<void> setChannelFixed(
      String channel, int modeId, int intensity) async {
    final ci = intensity.clamp(0, 276);
    logAction('set_channel_fixed', [channel, modeId, ci]);
    logStatus('⚡ $channel 模式$modeId 强度$ci/276');
  }

  Future<void> setChannelRealtime(String channel, int intensity,
      int frequency, int pulseWidth) async {
    final ci = intensity.clamp(0, 276);
    final cf = frequency.clamp(1, 100);
    final cp = pulseWidth.clamp(0, 100);
    logAction('set_channel_realtime', [channel, ci, cf, cp]);
    logStatus('⚡ $channel 实时 $ci级 ${cf}Hz ${cp}us');
  }

  Future<void> setMotor(int state) async {
    logAction('set_motor', [state]);
    logStatus('🔌 马达 ${state == 0 ? '关闭' : '开启'}');
  }

  Future<void> stopAll() async {
    logAction('stop_all', []);
    logStatus('🛑 所有通道已停止');
  }

  @override
  Future<void> emergencyStop() async {
    logAction('emergencyStop', []);
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
          await setChannelFixed('A', _i(args[1]), _i(args[0]));
        }
      case 'set_motor':
        await setMotor(_i(args.isNotEmpty ? args[0] : 0));
      case 'stop':
      case 'stop_all':
        await stopAll();
    }
  }

  int _i(dynamic v) =>
      v is int ? v : v is double ? v.round() : int.tryParse(v.toString()) ?? 0;

  String _s(dynamic v) => v.toString();
}

// ═════════════════════════════════════════════
// 灌肠机 · FakeDriver
// BLE FFB0 · 2泵 + 压力传感器
// ═════════════════════════════════════════════

class FakeEnemaDriver extends ToyDriver {
  int _simulatedPressure = 50;

  // 内部缓存最后一次 read_pressure 的结果，供 return 使用
  int _lastPressure = 50;

  FakeEnemaDriver({required super.toyId, super.toyName = '灌肠机'});

  @override
  Map<String, String> get apiFunctions => {
        'fill(seconds)': '注水，时间秒',
        'drain(seconds)': '排水，时间秒',
        'pause()': '暂停所有泵',
        'read_pressure()': '读取压力值 0-100',
        'get_battery()': '获取电量',
      };

  Future<void> fill(int seconds) async {
    logAction('fill', [seconds]);
    _simulatedPressure = (_simulatedPressure + seconds * 2).clamp(0, 100);
    logStatus('💧 注水 ${seconds}s 压力→$_simulatedPressure');
  }

  Future<void> drain(int seconds) async {
    logAction('drain', [seconds]);
    _simulatedPressure = (_simulatedPressure - seconds * 3).clamp(0, 100);
    logStatus('💧 排水 ${seconds}s 压力→$_simulatedPressure');
  }

  Future<void> pause() async {
    logAction('pause', []);
    logStatus('⏸️ 泵已暂停');
  }

  Future<int> readPressure() async {
    _simulatedPressure += (_simulatedPressure % 10 - 4);
    _simulatedPressure = _simulatedPressure.clamp(10, 100);
    _lastPressure = _simulatedPressure;
    logAction('read_pressure', []);
    logStatus('📊 压力值: $_lastPressure');
    return _lastPressure;
  }

  @override
  Future<dynamic> callMethodWithResult(
      String method, List<dynamic> args) async {
    if (method == 'read_pressure') return readPressure();
    await callMethod(method, args);
    return 0;
  }

  @override
  Future<int> getBattery() async => 85;

  @override
  Future<void> emergencyStop() async {
    logAction('emergencyStop', []);
    _simulatedPressure = 50;
    logStatus('🚨 紧急停止，泵已关闭');
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

  int _i(dynamic v) =>
      v is int ? v : v is double ? v.round() : int.tryParse(v.toString()) ?? 0;
}

// ═════════════════════════════════════════════
// 电子锁 · FakeDriver
// ═════════════════════════════════════════════

class FakeLockDriver extends ToyDriver {
  bool _locked = false;

  FakeLockDriver({required super.toyId, super.toyName = '电子锁'});

  @override
  Map<String, String> get apiFunctions => {
        'lock()': '上锁',
        'unlock()': '解锁',
      };

  Future<void> lock() async {
    _locked = true;
    logAction('lock', []);
    logStatus('🔒 已上锁');
  }

  Future<void> unlock() async {
    _locked = false;
    logAction('unlock', []);
    logStatus('🔓 已解锁');
  }

  bool get isLocked => _locked;

  @override
  Future<void> emergencyStop() async {
    _locked = false;
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
}
