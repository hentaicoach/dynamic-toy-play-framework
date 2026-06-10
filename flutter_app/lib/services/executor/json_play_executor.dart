import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'ast_types.dart';
import 'execution_ctx.dart';
import '../ble/toy_registry.dart';
import '../ble/drivers/toy_driver.dart';

/// JSON AST 玩法执行引擎
///
/// 递归 async walker，支持所有指令类型 + 表达式求值。
/// 取消机制使用 Future.any([_cancelCompleter.future, ...])。
///
/// 用法：
/// ```dart
/// final executor = JsonPlayExecutor(registry: registry);
/// executor.onPrint = (msg) => setState(() => logs.add(msg));
/// executor.onStateChange = (s) => setState(() => state = s);
/// final result = await executor.execute(playBody);
/// ```
class JsonPlayExecutor {
  final ToyRegistry registry;
  /// 执行状态
  ExecutionState _state = ExecutionState.idle;
  ExecutionState get state => _state;

  /// 打印输出
  List<String> get printOutput => _ctx?.printOutput ?? [];

  /// 当前行号
  int get currentLine => _ctx?.currentLine ?? 0;

  /// 总行数
  int get totalLines => _ctx?.totalLines ?? 0;

  /// 进度回调
  void Function(int current, int total)? onProgress;
  void Function(ExecutionState state)? onStateChange;
  void Function(String line)? onPrint;

  /// 执行上下文
  ExecutionCtx? _ctx;

  JsonPlayExecutor({required this.registry});

  /// 执行玩法脚本
  ///
  /// [playBody] — 反序列化后的 PlayBody 对象
  Future<ExecutionResult> execute(PlayBody playBody) async {
    _ctx = ExecutionCtx(registry: registry);
    _ctx!.reset();
    _ctx!.onProgress = onProgress;
    _ctx!.onPrint = onPrint;
    _ctx!.onStateChange = (s) {
      _state = s;
      onStateChange?.call(s);
    };

    _setState(ExecutionState.running);

    // 初始化变量
    for (final entry in playBody.vars.entries) {
      _ctx!.setVar(entry.key, entry.value);
    }

    // 计算总指令数（用于进度）
    _ctx!.totalLines = _countInstructions(playBody.body);

    try {
      await _execBlock(playBody.body, 0);
    } on _StopException {
      // 正常 return（顶层不处理）
    } on _BreakException {
      // 顶层的 break（兜住不崩）
    } on _CancelledException {
      await registry.stopAll();
      _setState(ExecutionState.stopped);
      return ExecutionResult(
        success: false,
        error: '用户取消',
        printOutput: _ctx!.printOutput,
        lineNumber: _ctx!.currentLine,
      );
    } catch (e) {
      debugPrint('[JsonPlayExecutor] Error: $e');
      _setState(ExecutionState.error);
      return ExecutionResult(
        success: false,
        error: e.toString(),
        printOutput: _ctx!.printOutput,
        lineNumber: _ctx!.currentLine,
      );
    }

    if (_ctx!.cancelled) {
      await registry.stopAll();
      _setState(ExecutionState.stopped);
      return ExecutionResult(
        success: false,
        error: '用户取消',
        printOutput: _ctx!.printOutput,
        lineNumber: _ctx!.currentLine,
      );
    }

    _setState(ExecutionState.completed);
    return ExecutionResult(
      success: true,
      printOutput: _ctx!.printOutput,
      lineNumber: _ctx!.currentLine,
    );
  }

  /// 取消执行
  void cancel() {
    _ctx?.cancel();
  }

  // ── 内部执行 ──

  /// 执行指令块（线性序列）
  Future<void> _execBlock(List<Instruction> instructions, int depth) async {
    if (depth > 50) {
      throw FormatException('递归嵌套过深，超过 50 层限制');
    }

    for (int i = 0; i < instructions.length && !_ctx!.cancelled; i++) {
      final inst = instructions[i];
      _ctx!.currentLine++;
      _ctx!.updateProgress(_ctx!.currentLine);
      await _execInstruction(inst, depth);
    }
  }

  /// 执行单条指令
  Future<void> _execInstruction(Instruction inst, int depth) async {
    switch (inst) {
      case ToyCallInst i:
        await _execToyCall(i);
      case WaitInst i:
        await _execWait(i);
      case AssignInst i:
        await _execAssign(i);
      case PrintInst i:
        _execPrint(i);
      case IfInst i:
        await _execIf(i, depth);
      case WhileInst i:
        await _execWhile(i, depth);
      case RepeatInst i:
        await _execRepeat(i, depth);
      case BreakInst _:
        throw _BreakException();
    }
  }

  // ── 指令执行器 ──

  Future<void> _execToyCall(ToyCallInst inst) async {
    final driver = registry[inst.toy];
    if (driver == null) {
      debugPrint('[JsonPlayExecutor] ⚠ 未注册的玩具: ${inst.toy}');
      registry.logError(inst.toy, '❌ 未注册: ${inst.toy}');
      return;
    }

    // 求值参数
    final args = <dynamic>[];
    for (final arg in inst.args) {
      args.add(await _evalExpr(arg));
    }

    await driver.callMethod(inst.method, args);
  }

  Future<void> _execWait(WaitInst inst) async {
    final ms = inst.ms;
    if (ms <= 0) return;

    // Future.any: 超时或取消
    await Future.any([
      _ctx!.cancelFuture,
      Future.delayed(Duration(milliseconds: ms)),
    ]);

    // 如果是被取消唤醒的（不是 wait 自然到期）
    if (_ctx!.cancelled) {
      throw _CancelledException();
    }
  }

  Future<void> _execAssign(AssignInst inst) async {
    final value = await _evalExpr(inst.expr);
    _ctx!.setVar(inst.name, value);
  }

  void _execPrint(PrintInst inst) {
    _ctx!.addPrint(inst.msg);
  }

  Future<void> _execIf(IfInst inst, int depth) async {
    final cond = await _evalExpr(inst.cond);
    if (_isTruthy(cond)) {
      await _execBlock(inst.thenBlock, depth + 1);
    } else if (inst.elseBlock.isNotEmpty) {
      await _execBlock(inst.elseBlock, depth + 1);
    }
  }

  Future<void> _execWhile(WhileInst inst, int depth) async {
    while (!_ctx!.cancelled) {
      final cond = await _evalExpr(inst.cond);
      if (!_isTruthy(cond)) break;

      try {
        await _execBlock(inst.body, depth + 1);
      } on _BreakException {
        break;
      }
    }
  }

  Future<void> _execRepeat(RepeatInst inst, int depth) async {
    int counter = 0;

    do {
      if (_ctx!.cancelled) break;

      try {
        await _execBlock(inst.body, depth + 1);
      } on _BreakException {
        break;
      }

      counter++;

      // times 模式
      if (inst.times != null && counter >= inst.times!) break;

      // until 模式
      if (inst.until != null) {
        final cond = await _evalExpr(inst.until!);
        if (_isTruthy(cond)) break;
      }
    } while (!_ctx!.cancelled);
  }

  // ── 表达式求值 ──

  Future<dynamic> _evalExpr(Expr expr) async {
    return switch (expr) {
      NumExpr e => e.value,
      StrExpr e => e.value,
      BoolExpr e => e.value,
      NilExpr _ => null,
      VarExpr e => _ctx!.getVar(e.name),
      BinopExpr e => _evalBinop(e),
      UnopExpr e => _evalUnop(e),
      ToyCallExpr e => _evalToyCallExpr(e),
    };
  }

  Future<dynamic> _evalBinop(BinopExpr expr) async {
    final left = await _evalExpr(expr.left);
    final right = await _evalExpr(expr.right);

    // 字符串拼接特殊处理
    if (expr.op == '..') {
      return '${left ?? ""}${right ?? ""}';
    }

    final l = _toNum(left);
    final r = _toNum(right);

    return switch (expr.op) {
      '+' => l + r,
      '-' => l - r,
      '*' => l * r,
      '/' => l / r,
      '%' => l % r,
      '^' => math.pow(l, r).toDouble(),
      '==' => l == r,
      '~=' => l != r,
      '>' => l > r,
      '<' => l < r,
      '>=' => l >= r,
      '<=' => l <= r,
      'and' => _isTruthy(left) ? right : left,
      'or' => _isTruthy(left) ? left : right,
      _ => throw FormatException('Unknown binary operator: ${expr.op}'),
    };
  }

  Future<dynamic> _evalUnop(UnopExpr expr) async {
    final x = await _evalExpr(expr.operand);
    return switch (expr.op) {
      'not' => !_isTruthy(x),
      '-' => -_toNum(x),
      '#' => _len(x),
      _ => throw FormatException('Unknown unary operator: ${expr.op}'),
    };
  }

  Future<dynamic> _evalToyCallExpr(ToyCallExpr expr) async {
    final driver = registry[expr.toy];
    if (driver == null) {
      debugPrint('[JsonPlayExecutor] ⚠ 未注册的玩具(表达式): ${expr.toy}');
      return 0;
    }

    final args = <dynamic>[];
    for (final arg in expr.args) {
      args.add(await _evalExpr(arg));
    }

    return await driver.callMethodWithResult(expr.method, args);
  }

  // ── 辅助函数 ──

  /// Lua 布尔上下文判断
  bool _isTruthy(dynamic value) {
    if (value == null) return false; // nil → false
    if (value is bool) return value;
    return true; // 0, 空字符串等在 Lua 中都是 true
  }

  /// 转为数值
  double _toNum(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    if (value is bool) return value ? 1.0 : 0.0;
    return 0.0;
  }

  /// 长度运算符 #
  int _len(dynamic value) {
    if (value == null) return 0;
    if (value is String) return value.length;
    if (value is List) return value.length;
    return 0;
  }

  /// 递归统计指令数（用于进度）
  int _countInstructions(List<Instruction> instructions) {
    int count = 0;
    for (final inst in instructions) {
      count++;
      switch (inst) {
        case IfInst i:
          count += _countInstructions(i.thenBlock);
          count += _countInstructions(i.elseBlock);
        case WhileInst i:
          count += _countInstructions(i.body);
        case RepeatInst i:
          count += _countInstructions(i.body);
        default:
          break;
      }
    }
    return count;
  }

  void _setState(ExecutionState s) {
    _state = s;
    _ctx?.setState(s);
  }
}

// ── 异常 ──

class _StopException implements Exception {}

class _BreakException implements Exception {}

class _CancelledException implements Exception {}
