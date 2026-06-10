/// 日志级别
enum LogLevel { debug, info, warn, error }

/// 全局日志帮助类 — debug 包输出全部日志，release 包只输出 info+
class Log {
  static LogLevel _level = LogLevel.info;

  /// 设置日志级别
  static void setLevel(LogLevel level) => _level = level;
  static LogLevel get currentLevel => _level;

  /// Debug 日志
  static void d(String message) {
    if (_level.index <= LogLevel.debug.index) {
      _print('[D]', message);
    }
  }

  /// Info 日志
  static void i(String message) {
    if (_level.index <= LogLevel.info.index) {
      _print('[I]', message);
    }
  }

  /// Warn 日志
  static void w(String message) {
    if (_level.index <= LogLevel.warn.index) {
      _print('[W]', message);
    }
  }

  /// Error 日志
  static void e(String message) {
    _print('[E]', message);
  }

  static void _print(String level, String message) {
    // ignore: avoid_print
    print('$level $message');
  }
}

class AppConstants {
  // Hermes API 服务地址（AVD 用 10.0.2.2，真机改回局域网 IP）
  static const String hermesHost = '10.0.2.2';
  static const int hermesPort = 8765;
  static String get hermesBaseUrl => 'http://$hermesHost:$hermesPort';

  // 玩具类型
  static const String toyTypeLock = 'lock';
  static const String toyTypeEnema = 'enema';
  static const String toyTypeEms = 'ems';
  static const String toyTypeMasturbator = 'masturbator';

  // BLE UUID
  static const String bleServiceEnema = '0000ffb0-0000-1000-8000-00805f9b34fb';
  static const String bleCharEnemaWrite = '0000ffb1-0000-1000-8000-00805f9b34fb';
  static const String bleCharEnemaNotify = '0000ffb2-0000-1000-8000-00805f9b34fb';

  static const String bleServiceEms = '0000ff30-0000-1000-8000-00805f9b34fb';
  static const String bleCharEmsWrite = '0000ff31-0000-1000-8000-00805f9b34fb';
  static const String bleCharEmsNotify = '0000ff32-0000-1000-8000-00805f9b34fb';

  static const String bleServiceVibrator = '0000ff40-0000-1000-8000-00805f9b34fb';
  static const String bleCharVibratorWrite = '0000ff41-0000-1000-8000-00805f9b34fb';
  static const String bleCharVibratorNotify = '0000ff42-0000-1000-8000-00805f9b34fb';

  // Lua 执行限制
  static const int maxScriptDurationMs = 300000; // 5分钟
  static const int maxScriptSize = 50000; // 50KB
  static const int maxBleWritePerSecond = 20;
}
