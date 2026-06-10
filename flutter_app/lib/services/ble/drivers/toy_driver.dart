import 'dart:async';

/// 玩具驱动基类
abstract class ToyDriver {
  final String toyId;
  final String toyName;

  ToyDriver({required this.toyId, required this.toyName});

  /// 玩具能力描述，用于生成 Agent 提示词
  Map<String, String> get apiFunctions;

  /// 日志回调（由 ToyRegistry 注入）
  void Function(DriverLogEntry entry)? onLog;

  /// 统一方法调用入口（Lua 执行器用）
  Future<void> callMethod(String method, List<dynamic> args) async {
    logAction(method, args);
    await dispatchMethod(method, args);
  }

  /// 子类重写此方法实现具体调用分发
  /// 注意：必须 public 才能被不同文件的子类 override
  Future<void> dispatchMethod(String method, List<dynamic> args) async {}

  /// 有返回值的调用（如 read_pressure）
  /// 默认返回 0，子类可重写
  Future<dynamic> callMethodWithResult(
      String method, List<dynamic> args) async {
    await callMethod(method, args);
    return 0;
  }

  /// 紧急停止
  Future<void> emergencyStop();

  /// 获取电池电量
  Future<int> getBattery() async => 100;

  /// 内部日志输出
  void _log(String level, String message) {
    onLog?.call(DriverLogEntry(
      timestamp: DateTime.now(),
      toyId: toyId,
      level: level,
      message: message,
    ));
  }

  void logAction(String method, List<dynamic> args) {
    final argStr = args.map((a) => a.toString()).join(', ');
    _log('ACTION', 'toy.$toyId:$method($argStr)');
  }

  void logStatus(String msg) {
    _log('STATUS', msg);
  }

  void logError(String msg) {
    _log('ERROR', msg);
  }
}

/// 驱动日志条目
class DriverLogEntry {
  final DateTime timestamp;
  final String toyId;
  final String level; // ACTION | STATUS | ERROR
  final String message;

  const DriverLogEntry({
    required this.timestamp,
    required this.toyId,
    required this.level,
    required this.message,
  });

  String get formatted {
    final t = timestamp.toString().substring(11, 23);
    return '[$t][$level][$toyId] $message';
  }
}

/// 执行状态枚举
enum ExecutionState { idle, running, paused, completed, stopped, error }
