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
