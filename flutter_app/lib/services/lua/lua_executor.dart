import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../ble/drivers/toy_driver.dart';
import '../ble/toy_registry.dart';

/// Lua 脚本执行引擎（简化版 — line-by-line 解析执行）
///
/// 支持 bondage_escape_penalty 所用的全部模式：
/// while/if/repeat/break/return · local 变量 · toy 调用 · wait · print · math
class LuaExecutor {
  final ToyRegistry registry;

  int currentLine = 0;
  int totalLines = 0;
  ExecutionState _state = ExecutionState.idle;
  ExecutionState get state => _state;

  void Function(int current, int total)? onProgress;
  void Function(ExecutionState state)? onStateChange;
  void Function(String line)? onPrint;

  bool _cancelled = false;
  final List<String> _printOutput = [];

  List<String> get printOutput => List.unmodifiable(_printOutput);

  LuaExecutor({required this.registry});

  void cancel() {
    _cancelled = true;
  }

  Future<ExecutionResult> execute(String lua) async {
    _cancelled = false;
    _printOutput.clear();
    _setState(ExecutionState.running);

    final lines = lua.split('\n');
    totalLines = lines.length;

    try {
      await _execScope(lines, 0, lines.length);
    } on _StopException {
      // 正常 return
    } on _BreakException {
      // 顶层的 break（不合法的 Lua，但兜住不崩）
    } catch (e) {
      _setState(ExecutionState.error);
      return ExecutionResult(
        success: false,
        error: e.toString(),
        printOutput: _printOutput,
        lineNumber: currentLine,
      );
    }

    if (_cancelled) {
      await registry.stopAll();
      _setState(ExecutionState.stopped);
      return ExecutionResult(
        success: false,
        error: '用户取消',
        printOutput: _printOutput,
        lineNumber: currentLine,
      );
    }

    _setState(ExecutionState.completed);
    return ExecutionResult(
      success: true,
      printOutput: _printOutput,
      lineNumber: currentLine,
    );
  }

  // ── 递归作用域执行 ──

  Future<void> _execScope(
      List<String> lines, int start, int end) async {
    final vars = <String, dynamic>{};
    int i = start;

    while (i < end && !_cancelled) {
      currentLine = i + 1;
      final raw = lines[i].trim();
      i++;

      onProgress?.call(currentLine, totalLines);

      if (raw.isEmpty || raw.startsWith('--')) continue;

      // === 控制流 ===
      if (raw.startsWith('while ')) {
        final condStr = _extractWhileCond(raw);
        // 从 while 下一行开始找匹配的 end，初始深度 1（while 自身）
        final loopEnd = _findMatchingEnd(lines, i, 1);
        if (loopEnd < i) continue;

        while (_evalCond(condStr, vars) && !_cancelled) {
          try {
            await _execScope(lines, i, loopEnd);
          } on _BreakException {
            break;
          }
        }
        i = loopEnd + 1;
        continue;
      }

      if (raw.startsWith('repeat')) {
        final untilLine = _findMatchingUntil(lines, i, 1);
        if (untilLine < 0) continue;
        final untilRaw = lines[untilLine].trim();
        final condStr = untilRaw.substring(5).trim();

        do {
          try {
            await _execScope(lines, i, untilLine);
          } on _BreakException {
            break;
          }
          if (_cancelled) break;
        } while (!_evalCond(condStr, vars) && !_cancelled);

        i = untilLine + 1;
        continue;
      }

      if (raw.startsWith('if ')) {
        final condStr = _extractIfCond(raw);
        // if 自身贡献 1 层深度
        final elseLine = _findElseLine(lines, i, 1);
        final ifEnd = _findMatchingEnd(lines, i, 1);
        if (ifEnd < 0) continue;

        if (_evalCond(condStr, vars)) {
          await _execScope(lines, i, elseLine >= 0 ? elseLine : ifEnd);
        } else if (elseLine >= 0) {
          await _execScope(lines, elseLine + 1, ifEnd);
        }
        i = ifEnd + 1;
        continue;
      }

      if (raw == 'end' || raw.startsWith('else') || raw.startsWith('until')) {
        continue; // 由外层控制
      }

      if (raw == 'break') {
        throw _BreakException();
      }

      if (raw == 'return') {
        throw _StopException();
      }

      // === 语句 ===
      if (raw.startsWith('toy.') || raw.startsWith('toy_') || raw.startsWith('toy[')) {
        await _execToyCall(raw);
      } else if (raw.startsWith('wait(')) {
        await _execWait(raw);
      } else if (raw.startsWith('print(')) {
        _execPrint(raw, vars);
      } else if (raw.startsWith('local ')) {
        await _execLocal(raw, vars);
      } else if (raw.contains('=')) {
        await _execAssignment(raw, vars);
      } else {
        debugPrint('[Lua] ⚠ 未识别行($currentLine): $raw');
      }
    }
  }

  // ── 控制流辅助 ──

  String _extractWhileCond(String raw) {
    // while xxx do
    final m = RegExp(r'while\s+(.+)\s+do').firstMatch(raw);
    return m?.group(1)?.trim() ?? 'true';
  }

  String _extractIfCond(String raw) {
    // if xxx then
    final m = RegExp(r'if\s+(.+)\s+then').firstMatch(raw);
    return m?.group(1)?.trim() ?? 'true';
  }

  int _findMatchingEnd(List<String> lines, int start, [int initialDepth = 0]) {
    int depth = initialDepth;
    for (int j = start; j < lines.length; j++) {
      final l = lines[j].trim();
      if (l.startsWith('while ') || l.startsWith('if ') || l.startsWith('repeat')) depth++;
      if (l == 'end' || l.startsWith('until')) {
        if (depth <= 0) return j;
        depth--;
      }
    }
    return -1;
  }

  int _findElseLine(List<String> lines, int start, [int initialDepth = 0]) {
    int depth = initialDepth;
    for (int j = start; j < lines.length; j++) {
      final l = lines[j].trim();
      if (l.startsWith('if ')) depth++;
      if (l.startsWith('else') && depth <= 0) return j;
      if (l == 'end') {
        if (depth <= 0) return -1;
        depth--;
      }
    }
    return -1;
  }

  int _findMatchingUntil(List<String> lines, int start, [int initialDepth = 0]) {
    int depth = initialDepth;
    for (int j = start; j < lines.length; j++) {
      final l = lines[j].trim();
      if (l.startsWith('repeat')) depth++;
      if (l.startsWith('until') && depth <= 0) return j;
    }
    return -1;
  }

  // ── 条件求值 ──

  bool _evalCond(String expr, Map<String, dynamic> vars) {
    if (expr == 'true') return true;
    if (expr == 'false') return false;

    // 比较运算
    for (final op in ['>=', '<=', '~=', '>', '<', '==']) {
      final idx = expr.indexOf(op);
      if (idx > 0) {
        final left = _evalExpr(expr.substring(0, idx).trim(), vars);
        final right = _evalExpr(expr.substring(idx + op.length).trim(), vars);
        switch (op) {
          case '>=': return left >= right;
          case '<=': return left <= right;
          case '>': return left > right;
          case '<': return left < right;
          case '==': return left == right;
          case '~=': return left != right;
        }
      }
    }

    final v = _evalExpr(expr, vars);
    return v != 0.0;
  }

  double _evalExpr(String expr, Map<String, dynamic> vars) {
    final n = double.tryParse(expr);
    if (n != null) return n;

    if (vars.containsKey(expr)) {
      final v = vars[expr]!;
      return (v is num) ? v.toDouble() : 0.0;
    }

    // math.floor(x)
    final m = RegExp(r'math\.(floor|ceil|max|min)\((.+)\)').firstMatch(expr);
    if (m != null) {
      final fn = m.group(1)!;
      final inner = m.group(2)!;
      if (fn == 'floor') return _evalExpr(inner, vars).floorToDouble();
      if (fn == 'ceil') return _evalExpr(inner, vars).ceilToDouble();
      // max/min with two args
      final commaIdx = _findComma(inner);
      if (commaIdx >= 0) {
        final a = _evalExpr(inner.substring(0, commaIdx).trim(), vars);
        final b = _evalExpr(inner.substring(commaIdx + 1).trim(), vars);
        return fn == 'max' ? math.max(a, b) : math.min(a, b);
      }
    }

    return 0.0;
  }

  int _findComma(String s) {
    int depth = 0;
    for (int i = 0; i < s.length; i++) {
      if (s[i] == '(') depth++;
      if (s[i] == ')') depth--;
      if (s[i] == ',' && depth == 0) return i;
    }
    return -1;
  }

  // ── 语句执行 ──

  /// 解析 Lua 调用参数列表
  List<dynamic> _parseArgs(String argsStr) {
    if (argsStr.trim().isEmpty) return [];
    return argsStr.split(',').map((s) {
      final t = s.trim();
      final n = num.tryParse(t);
      if (n != null) return n;
      if ((t.startsWith('"') && t.endsWith('"')) ||
          (t.startsWith("'") && t.endsWith("'"))) {
        return t.substring(1, t.length - 1);
      }
      return t;
    }).toList();
  }

  /// 从行中提取 toy 调用 (toy.xxx, toy_xxx, xxx:method)
  (String id, String method, String argsStr)? _extractToyCall(String line) {
    // 策略1: toy.xxx:method(args)
    var m = RegExp(r'toy\.(\w+):(\w+)\(([^)]*)\)').firstMatch(line);
    if (m != null) {
      return (m.group(1)!, m.group(2)!, m.group(3)!);
    }
    // 策略2: toy_xxx:method(args) — AI 偶尔用下划线
    m = RegExp(r'toy_(\w+):(\w+)\(([^)]*)\)').firstMatch(line);
    if (m != null) {
      return (m.group(1)!, m.group(2)!, m.group(3)!);
    }
    // 策略3: xxx:method(args) — 无前缀（仅当整行没有 toy 前缀时才触发）
    if (!line.contains(RegExp(r'toy[._\[]'))) {
      m = RegExp(r'(\w+):(\w+)\(([^)]*)\)').firstMatch(line);
      if (m != null) {
        return (m.group(1)!, m.group(2)!, m.group(3)!);
      }
    }
    // 策略4: toy[xxx]:method(args) — AI 偶尔用方括号
    m = RegExp(r'toy\[(\w+)\]:(\w+)\(([^)]*)\)').firstMatch(line);
    if (m != null) {
      return (m.group(1)!, m.group(2)!, m.group(3)!);
    }
    return null;
  }

  Future<void> _execToyCall(String line) async {
    final parsed = _extractToyCall(line);
    if (parsed == null) {
      debugPrint('[Lua] ⚠ 无法解析 toy 调用: $line');
      return;
    }
    final (id, method, argsStr) = parsed;

    final driver = registry[id];
    if (driver == null) {
      debugPrint('[Lua] ⚠ 未注册的玩具: $id');
      registry.logError(id, '❌ 未注册: $id');
      return;
    }

    final args = _parseArgs(argsStr);
    await driver.callMethod(method, args);
  }

  Future<void> _execWait(String line) async {
    final m = RegExp(r'wait\((\d+)\)').firstMatch(line);
    if (m == null) return;
    final ms = int.tryParse(m.group(1)!) ?? 0;
    if (ms <= 0) return;
    await Future.delayed(Duration(milliseconds: ms));
  }

  void _execPrint(String line, Map<String, dynamic> vars) {
    var content = line.substring(6, line.length - 1); // print(...)
    // 处理字符串拼接
    if (content.contains('..')) {
      content = content.split('..').map((s) {
        final t = s.trim();
        if ((t.startsWith('"') && t.endsWith('"')) ||
            (t.startsWith("'") && t.endsWith("'"))) {
          return t.substring(1, t.length - 1);
        }
        if (vars.containsKey(t)) return vars[t].toString();
        return t;
      }).join('');
    }
    // 去掉外围引号
    content = content.trim();
    if ((content.startsWith('"') && content.endsWith('"')) ||
        (content.startsWith("'") && content.endsWith("'"))) {
      content = content.substring(1, content.length - 1);
    }
    _printOutput.add(content);
    onPrint?.call(content);
    debugPrint('[Lua:print] $content');
  }

  Future<void> _execLocal(String line, Map<String, dynamic> vars) async {
    final m = RegExp(r'local\s+(\w+)\s*=\s*(.+)').firstMatch(line);
    if (m == null) return;
    final name = m.group(1)!;
    final expr = m.group(2)!.trim();

    // 处理右值是 toy 调用（如 local p = toy.enema_1:read_pressure()）
    final tc = _extractToyCall(expr);
    if (tc != null) {
      final (id, method, argsStr) = tc;

      final driver = registry[id];
      if (driver != null) {
        final args = _parseArgs(argsStr);
        final result = await driver.callMethodWithResult(method, args);
        vars[name] = result;
      }
      return;
    }

    // 数字
    final n = double.tryParse(expr);
    if (n != null) {
      vars[name] = n;
      return;
    }
    // 变量引用
    if (vars.containsKey(expr)) {
      vars[name] = vars[expr];
      return;
    }
    // 字符串
    if ((expr.startsWith('"') && expr.endsWith('"')) ||
        (expr.startsWith("'") && expr.endsWith("'"))) {
      vars[name] = expr.substring(1, expr.length - 1);
      return;
    }
    // 计算表达式
    vars[name] = _evalExpr(expr, vars);
  }

  Future<void> _execAssignment(String line, Map<String, dynamic> vars) async {
    final m = RegExp(r'(\w+)\s*=\s*(.+)').firstMatch(line);
    if (m == null) return;
    final name = m.group(1)!;
    final expr = m.group(2)!.trim();

    // 右值是 toy 调用
    final tc = _extractToyCall(expr);
    if (tc != null) {
      final (id, method, argsStr) = tc;

      final driver = registry[id];
      if (driver != null) {
        final args = _parseArgs(argsStr);
        final result = await driver.callMethodWithResult(method, args);
        vars[name] = result;
      }
      return;
    }

    vars[name] = _evalExpr(expr, vars);
  }

  void _setState(ExecutionState s) {
    _state = s;
    onStateChange?.call(s);
  }
}

// ── 异常 ──

class _StopException implements Exception {}
class _BreakException implements Exception {}

// ── 结果 ──

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
