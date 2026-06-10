import 'dart:async';
import 'package:flutter/foundation.dart';
import '../ble/toy_registry.dart';
import '../ble/drivers/toy_driver.dart';

/// 执行上下文 — 管理变量、取消信号、进度回调
///
/// 设计要点：
/// - Flat 变量作用域（全局 Map，无块级作用域）
/// - Future.any 取消机制（cancel 时中断所有 pending wait）
/// - 未定义变量读时返回 0（等 Lua 语义）
class ExecutionCtx {
  /// 全局变量表
  final Map<String, dynamic> vars = {};

  /// 取消信号
  bool cancelled = false;

  /// 取消 completer — 用于在 wait() 时中断 Future.any
  Completer<void> _cancelCompleter = Completer<void>();

  /// 当前执行进度
  int currentLine = 0;
  int totalLines = 0;

  /// 打印输出缓存
  final List<String> printOutput = [];

  /// 玩具注册表
  final ToyRegistry? registry;

  ExecutionCtx({this.registry});

  // ── 变量操作 ──

  /// 读取变量，未定义返回 0（等 Lua 语义）
  dynamic getVar(String name) {
    if (vars.containsKey(name)) return vars[name];
    return 0;
  }

  /// 设置变量
  void setVar(String name, dynamic value) {
    vars[name] = value;
  }

  // ── 取消 ──

  /// 触发取消
  void cancel() {
    cancelled = true;
    if (!_cancelCompleter.isCompleted) {
      _cancelCompleter.complete();
    }
  }

  /// 获取取消等待 future — 用于 Future.any
  Future<void> get cancelFuture => _cancelCompleter.future;

  /// 重置取消状态（新一次执行前调用）
  void reset() {
    cancelled = false;
    _cancelCompleter = Completer<void>();
    printOutput.clear();
    currentLine = 0;
    totalLines = 0;
  }

  // ── 进度 ──

  void Function(int current, int total)? onProgress;
  void Function(String line)? onPrint;
  void Function(ExecutionState state)? onStateChange;

  /// 更新行进度
  void updateProgress(int line) {
    currentLine = line;
    onProgress?.call(currentLine, totalLines);
  }

  /// 记录打印输出
  void addPrint(String msg) {
    printOutput.add(msg);
    onPrint?.call(msg);
    debugPrint('[Lua:print] $msg');
  }

  /// 状态变更
  void setState(ExecutionState state) {
    onStateChange?.call(state);
  }
}

/// 执行结果
class ExecutionResult {
  final bool success;
  final String? error;
  final List<String> printOutput;
  final int lineNumber;

  const ExecutionResult({
    required this.success,
    this.error,
    required this.printOutput,
    required this.lineNumber,
  });
}
