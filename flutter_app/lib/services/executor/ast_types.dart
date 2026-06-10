import 'dart:convert';

/// JSON AST 节点类型定义 + JSON 反序列化
///
/// 对应设计文档 docs/07-json-ast-executor.md §3-4
///
/// 使用方式：
/// ```
/// final playBody = PlayBody.fromJson(jsonDecode(jsonStr));
/// final executor = JsonPlayExecutor(registry: registry);
/// await executor.execute(playBody);
/// ```

// ═════════════════════════════════════════════
// 顶层执行体
// ═════════════════════════════════════════════

class PlayBody {
  final Map<String, double> vars;
  final List<Instruction> body;

  PlayBody({required this.vars, required this.body});

  factory PlayBody.fromJson(Map<String, dynamic> json) {
    final rawVars = json['vars'] as Map<String, dynamic>? ?? {};
    final vars = rawVars.map((k, v) => MapEntry(k, (v as num).toDouble()));

    final rawBody = json['body'] as List<dynamic>? ?? [];
    final body = rawBody
        .map((e) => Instruction.fromJson(e as Map<String, dynamic>))
        .toList();

    return PlayBody(vars: vars, body: body);
  }
}

// ═════════════════════════════════════════════
// 指令系统
// ═════════════════════════════════════════════

sealed class Instruction {
  const Instruction();

  factory Instruction.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'toy_call' => ToyCallInst.fromJson(json),
      'wait' => WaitInst.fromJson(json),
      'assign' => AssignInst.fromJson(json),
      'print' => PrintInst.fromJson(json),
      'if' => IfInst.fromJson(json),
      'while' => WhileInst.fromJson(json),
      'repeat' => RepeatInst.fromJson(json),
      'break' => BreakInst(),
      _ => throw FormatException('Unknown instruction type: $type'),
    };
  }
}

class ToyCallInst extends Instruction {
  final String toy;
  final String method;
  final List<Expr> args;

  ToyCallInst({required this.toy, required this.method, required this.args});

  factory ToyCallInst.fromJson(Map<String, dynamic> json) {
    final rawArgs = json['args'] as List<dynamic>? ?? [];
    final args = rawArgs.map((e) {
      if (e is Map<String, dynamic>) return Expr.fromJson(e);
      // 普通值 → 包装成字面量
      return Expr.fromValue(e);
    }).toList();

    return ToyCallInst(
      toy: json['toy'] as String,
      method: json['method'] as String,
      args: args,
    );
  }
}

class WaitInst extends Instruction {
  final int ms;

  WaitInst({required this.ms});

  factory WaitInst.fromJson(Map<String, dynamic> json) {
    return WaitInst(ms: (json['ms'] as num).toInt());
  }
}

class AssignInst extends Instruction {
  final String name;
  final Expr expr;

  AssignInst({required this.name, required this.expr});

  factory AssignInst.fromJson(Map<String, dynamic> json) {
    return AssignInst(
      name: json['name'] as String,
      expr: _parseExprField(json, 'expr'),
    );
  }
}

class PrintInst extends Instruction {
  final Expr msg;

  PrintInst({required this.msg});

  factory PrintInst.fromJson(Map<String, dynamic> json) {
    final raw = json['msg'];
    Expr msg;
    if (raw is Map<String, dynamic>) {
      msg = Expr.fromJson(raw);
    } else {
      msg = StrExpr(raw?.toString() ?? '');
    }
    return PrintInst(msg: msg);
  }
}

class IfInst extends Instruction {
  final Expr cond;
  final List<Instruction> thenBlock;
  final List<Instruction> elseBlock;

  IfInst({
    required this.cond,
    required this.thenBlock,
    required this.elseBlock,
  });

  factory IfInst.fromJson(Map<String, dynamic> json) {
    final rawThen = json['then'] as List<dynamic>? ?? [];
    final rawElse = json['else'] as List<dynamic>? ?? [];

    return IfInst(
      cond: _parseExprField(json, 'cond'),
      thenBlock: rawThen
          .map((e) => Instruction.fromJson(e as Map<String, dynamic>))
          .toList(),
      elseBlock: rawElse
          .map((e) => Instruction.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class WhileInst extends Instruction {
  final Expr cond;
  final List<Instruction> body;

  WhileInst({required this.cond, required this.body});

  factory WhileInst.fromJson(Map<String, dynamic> json) {
    final rawBody = json['body'] as List<dynamic>? ?? [];
    return WhileInst(
      cond: _parseExprField(json, 'cond'),
      body: rawBody
          .map((e) => Instruction.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class RepeatInst extends Instruction {
  final List<Instruction> body;
  final Expr? until;
  final int? times;

  RepeatInst({required this.body, this.until, this.times});

  factory RepeatInst.fromJson(Map<String, dynamic> json) {
    final rawBody = json['body'] as List<dynamic>? ?? [];
    final body = rawBody
        .map((e) => Instruction.fromJson(e as Map<String, dynamic>))
        .toList();

    Expr? until;
    if (json['until'] != null) {
      until = _parseExprField(json, 'until');
    }

    final times = json['times'] as int?;

    return RepeatInst(body: body, until: until, times: times);
  }
}

class BreakInst extends Instruction {}

// ═════════════════════════════════════════════
// 表达式系统
// ═════════════════════════════════════════════

sealed class Expr {
  const Expr();

  factory Expr.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'num' => NumExpr((json['value'] as num).toDouble()),
      'str' => StrExpr(json['value'] as String),
      'bool' => BoolExpr(json['value'] as bool),
      'nil' => NilExpr(),
      'var' => VarExpr(json['name'] as String),
      'binop' => BinopExpr.fromJson(json),
      'unop' => UnopExpr.fromJson(json),
      'toy_call' => ToyCallExpr.fromJson(json),
      _ => throw FormatException('Unknown expression type: $type'),
    };
  }

  /// 从 JSON 值（非类型标记值）创建字面量表达式
  factory Expr.fromValue(dynamic value) {
    if (value == null) return NilExpr();
    if (value is num) return NumExpr(value.toDouble());
    if (value is bool) return BoolExpr(value);
    if (value is String) return StrExpr(value);
    throw FormatException('Unsupported literal value type: ${value.runtimeType}');
  }
}

class NumExpr extends Expr {
  final double value;
  NumExpr(this.value);
}

class StrExpr extends Expr {
  final String value;
  StrExpr(this.value);
}

class BoolExpr extends Expr {
  final bool value;
  BoolExpr(this.value);
}

class NilExpr extends Expr {}

class VarExpr extends Expr {
  final String name;
  VarExpr(this.name);
}

class BinopExpr extends Expr {
  final String op;
  final Expr left;
  final Expr right;

  BinopExpr({required this.op, required this.left, required this.right});

  factory BinopExpr.fromJson(Map<String, dynamic> json) {
    return BinopExpr(
      op: json['op'] as String,
      left: _parseExprField(json, 'l'),
      right: _parseExprField(json, 'r'),
    );
  }
}

class UnopExpr extends Expr {
  final String op;
  final Expr operand;

  UnopExpr({required this.op, required this.operand});

  factory UnopExpr.fromJson(Map<String, dynamic> json) {
    return UnopExpr(
      op: json['op'] as String,
      operand: _parseExprField(json, 'x'),
    );
  }
}

class ToyCallExpr extends Expr {
  final String toy;
  final String method;
  final List<Expr> args;

  ToyCallExpr({required this.toy, required this.method, required this.args});

  factory ToyCallExpr.fromJson(Map<String, dynamic> json) {
    final rawArgs = json['args'] as List<dynamic>? ?? [];
    final args = rawArgs.map((e) {
      if (e is Map<String, dynamic>) return Expr.fromJson(e);
      return Expr.fromValue(e);
    }).toList();

    return ToyCallExpr(
      toy: json['toy'] as String,
      method: json['method'] as String,
      args: args,
    );
  }
}

/// 从 JSON map 中解析表达式字段，兼容 Map（表达式对象）或字面值
Expr _parseExprField(Map<String, dynamic> json, String key) {
  final raw = json[key];
  if (raw is Map<String, dynamic>) return Expr.fromJson(raw);
  return Expr.fromValue(raw);
}
