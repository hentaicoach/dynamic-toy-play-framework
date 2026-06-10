# JSON AST 玩法执行引擎 · 设计文档

> 版本：v2.0  
> 日期：2026-06-10  
> 目标：用 JSON AST 替换 LuaExecutor，实现结构化玩法脚本执行  
> 状态：设计锁定，待编码

---

## 目录

1. [设计背景](#1-设计背景)
2. [架构总览](#2-架构总览)
3. [JSON AST Schema 定义](#3-json-ast-schema-定义)
4. [表达式系统](#4-表达式系统)
5. [Async Walker 设计](#5-async-walker-设计)
6. [执行上下文与变量系统](#6-执行上下文与变量系统)
7. [Cancel 与错误处理](#7-cancel-与错误处理)
8. [Playbook 元数据格式](#8-playbook-元数据格式)
9. [迁移计划](#9-迁移计划)
10. [Agent Skill 设计要点](#10-agent-skill-设计要点)
11. [附录：完整示例](#11-附录完整示例)

---

## 1. 设计背景

### 1.1 动机

当前实现的 `LuaExecutor`（`lib/services/lua/lua_executor.dart`）是一个手写的逐行正则解析器，存在以下问题：

| 问题 | 具体表现 |
|------|---------|
| **语法覆盖不全** | 只支持 while/if/repeat 子集，不支持 for/until 正确语义 |
| **Bug 存在** | `_findMatchingEnd` depth 初始值不一致导致嵌套控制流错位 |
| **表达式求值弱** | 自写 `_evalExpr` 不支持 `not`/`nil`/`..`/复杂嵌套 |
| **LLM 生成不稳定** | Lua 文本格式无强约束，AI 容易生成语法错误 |

### 1.2 设计目标

```
┌─────────────┐     ┌──────────────────┐     ┌────────────────┐
│ DeepSeek /  │     │                  │     │                │
│ Hermes      │────→│  JSON AST IR     │────→│  Async Walker  │
│ (NLP→JSON)  │     │  (结构化指令树)   │     │  (递归执行)     │
└─────────────┘     └──────────────────┘     └────────────────┘
       ↑                      ↑                       ↑
   重新调教 skill      Dart 强类型定义          Future.any cancel
   structured output    schema 可校验          原生 async wait
```

核心设计决定：

- **粒度**：② — if/while/repeat + 嵌套 body + 变量
- **表达式格式**：JSON 字典树（嵌套 `op`/`l`/`r`）
- **Walker 模式**：递归 async walker
- **变量作用域**：Flat（全局 `Map`）
- **Cancel 机制**：`Future.any([_cancelCompleter.future, ...])`
- **Toy 返回值**：`assign` 内嵌 `toy_call` 作为表达式

---

## 2. 架构总览

```
┌──────────────────────────────────────────────────────────────────┐
│                        ExecutionPage                             │
│  ┌─────────────┐   ┌────────────────────┐   ┌────────────────┐  │
│  │  Playbook   │   │  JsonPlayExecutor  │   │  ToyRegistry   │  │
│  │  (元数据+   │──→│  (AST Walker)      │──→│  (ToyDriver[]) │  │
│  │   JSON AST) │   │  ┌──────────────┐  │   │                │  │
│  └─────────────┘   │  │ RecursiveWalker│  │   │ enema_1      │  │
│                    │  │  execBlock()   │  │   │ mast_1       │  │
│                    │  │  execIf()      │  │   │ egg_1        │  │
│                    │  │  execWhile()   │  │   │ plug_1       │  │
│                    │  │  execRepeat()  │  │   └────────────────┘  │
│                    │  │  execWait()    │  │                      │
│                    │  │  evalExpr()    │  │                      │
│                    │  └──────────────┘  │                      │
│                    │  ┌──────────────┐  │                      │
│                    │  │ ExecutionCtx  │  │                      │
│                    │  │  vars: Map    │  │                      │
│                    │  │  cancel: Bool │  │                      │
│                    │  │  cancelComp   │  │                      │
│                    │  └──────────────┘  │                      │
│                    └────────────────────┘                      │
└──────────────────────────────────────────────────────────────────┘
```

### 2.1 组件职责

| 组件 | 文件 | 职责 |
|------|------|------|
| `JsonPlayExecutor` | `services/executor/json_play_executor.dart` | AST 执行引擎，取 JSON → 递归执行 |
| `JsonPlayAst` | `services/executor/ast_types.dart` | AST 节点 Dart 类型定义 + JSON 反序列化 |
| `ExecutionCtx` | `services/executor/execution_ctx.dart` | 运行时上下文（变量、取消、进度） |
| `Playbook` | 已有模型 | 元数据（元数据层不变，增加 jsonPlay 字段） |

---

## 3. JSON AST Schema 定义

### 3.1 顶层结构

```json
{
  "version": 2,
  "name": "渐进调教",
  "toy_ids": ["mast_1", "enema_1"],
  "duration_sec": 180,
  "steps": [
    {"time_sec": 0,  "desc": "温柔试探，20% 速度"},
    {"time_sec": 10, "desc": "逐步加压"},
    {"time_sec": 60, "desc": "维持高压"}
  ],
  "play": {
    "vars": {"tolerance": 30},
    "body": [ ... ]
  }
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `version` | int | ✅ | 固定 `2` |
| `name` | string | ✅ | 玩法名称 |
| `toy_ids` | string[] | 可选 | 需要的玩具 ID 列表（UI 预检） |
| `duration_sec` | int | 可选 | 总时长秒数（进度条） |
| `steps` | StepMeta[] | 可选 | 可读步骤大纲（UI 显示） |
| `play` | PlayBody | ✅ | 执行体主体 |

### 3.2 PlayBody — 执行体

```json
{
  "vars": {
    "tolerance": 30,
    "max_pressure": 80
  },
  "body": [ <Instruction>, ... ]
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `vars` | object (string→number) | 可选 | 顶层变量初始化 |
| `body` | Instruction[] | ✅ | 指令序列 |

### 3.3 指令类型

所有指令共用基结构：

```typescript
interface Instruction {
  type: string;  // 指令类型标识
  // + 各类型独有字段
}
```

#### `toy_call` — 玩具方法调用

```json
{
  "type": "toy_call",
  "toy": "enema_1",
  "method": "set_speed",
  "args": [50]
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `toy` | string | ✅ | 玩具注册 ID |
| `method` | string | ✅ | 方法名 |
| `args` | Expr[] | 可选 | 参数列表（每个参数都是表达式） |

#### `wait` — 等待

```json
{
  "type": "wait",
  "ms": 2000
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `ms` | int | ✅ | 等待毫秒数 |

#### `assign` — 变量赋值

```json
{
  "type": "assign",
  "name": "cur_pressure",
  "expr": { "type": "toy_call", "toy": "enema_1", "method": "read_pressure", "args": [] }
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `name` | string | ✅ | 变量名 |
| `expr` | Expr | ✅ | 右侧表达式 |

#### `print` — 输出日志

```json
{
  "type": "print",
  "msg": "压力值: ${cur_pressure}"
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `msg` | string | ✅ | 输出文本（暂不支持表达式插值，仅字面量，后续可扩展） |

#### `if` — 条件分支

```json
{
  "type": "if",
  "cond": { "op": ">", "l": { "type": "var", "name": "cur_pressure" }, "r": { "type": "num", "value": 80 } },
  "then": [
    { "type": "toy_call", "toy": "enema_1", "method": "set_speed", "args": [0] },
    { "type": "print", "msg": "压力过高！停止" }
  ],
  "else": [
    { "type": "toy_call", "toy": "enema_1", "method": "set_speed", "args": [40] }
  ]
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cond` | Expr | ✅ | 条件表达式（求值为 boolean） |
| `then` | Instruction[] | ✅ | 条件为真时执行的指令序列 |
| `else` | Instruction[] | 可选 | 条件为假时执行的指令序列 |

#### `while` — 条件循环

```json
{
  "type": "while",
  "cond": { "op": "<=", "l": { "type": "var", "name": "cur_pressure" }, "r": { "type": "num", "value": 60 } },
  "body": [
    { "type": "toy_call", "toy": "enema_1", "method": "set_speed", "args": [80] },
    { "type": "wait", "ms": 2000 },
    { "type": "assign", "name": "cur_pressure", "expr": { "type": "toy_call", "toy": "enema_1", "method": "read_pressure", "args": [] } }
  ]
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cond` | Expr | ✅ | 循环条件 |
| `body` | Instruction[] | ✅ | 循环体 |

#### `repeat` — 重复循环

支持两种终止方式：

**until 模式（等 Lua 语义）：**

```json
{
  "type": "repeat",
  "body": [
    { "type": "toy_call", "toy": "mast_1", "method": "set_speed", "args": [80] },
    { "type": "wait", "ms": 1000 }
  ],
  "until": { "op": ">=", "l": { "type": "var", "name": "counter" }, "r": { "type": "num", "value": 5 } }
}
```

**times 模式（语法糖）：**

```json
{
  "type": "repeat",
  "body": [ ... ],
  "times": 5
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `body` | Instruction[] | ✅ | 循环体 |
| `until` | Expr | 互斥 | 条件满足时终止（至少执行一次 body） |
| `times` | int | 互斥 | 固定重复次数 |

**约束**：`until` 和 `times` 互斥，不能同时存在。

#### `break` — 跳出循环

```json
{
  "type": "break"
}
```

无参。只能在 `while`/`repeat` 的 body 内有效。

---

## 4. 表达式系统

### 4.1 表达式类型

所有表达式都共享基结构：

```json
{ "type": "<expr_type>", ... }
```

#### 字面量

```json
{ "type": "num", "value": 42 }       // 数值字面量
{ "type": "str", "value": "hello" }   // 字符串字面量
{ "type": "bool", "value": true }     // 布尔字面量
{ "type": "nil" }                     // nil 值
```

#### 变量引用

```json
{ "type": "var", "name": "cur_pressure" }
```

#### 二元运算

```json
{
  "type": "binop",
  "op": ">",
  "l": { "type": "var", "name": "cur_pressure" },
  "r": { "type": "num", "value": 80 }
}
```

| 操作符 | 语义 |
|--------|------|
| `+` `-` `*` `/` `%` `^` | 算术运算 |
| `==` `~=` `>` `<` `>=` `<=` | 比较运算 |
| `and` `or` | 逻辑运算（短路） |
| `..` | 字符串拼接 |

#### 一元运算

```json
{
  "type": "unop",
  "op": "not",
  "x": { "type": "bool", "value": false }
}
```

| 操作符 | 语义 |
|--------|------|
| `not` | 逻辑非 |
| `-` | 数值取反 |
| `#` | 长度运算符 |

#### Toy 调用作为表达式

```json
{
  "type": "toy_call",
  "toy": "enema_1",
  "method": "read_pressure",
  "args": []
}
```

toy_call 作表达式时**必须有返回值**（调用 `callMethodWithResult`）。

### 4.2 求值规则

```dart
Future<dynamic> evalExpr(Expr expr, ExecutionCtx ctx) async {
  switch (expr.type) {
    case 'num':   return expr.value;
    case 'str':   return expr.value;
    case 'bool':  return expr.value;
    case 'nil':   return null;
    case 'var':   return ctx.vars[expr.name];
    case 'binop': return await evalBinop(expr, ctx);
    case 'unop':  return await evalUnop(expr, ctx);
    case 'toy_call': return await evalToyCallExpr(expr, ctx);
  }
}
```

布尔上下文判断（用在 `if`/`while` 的 cond）：

- `null` / `false` → 假
- 其他值 → 真（包括 `0`、空字符串等 — 等 Lua 语义）

---

## 5. Async Walker 设计

### 5.1 顶层 API

```dart
class JsonPlayExecutor {
  final ToyRegistry registry;

  ExecutionState state = ExecutionState.idle;
  int currentLine = 0;

  void Function(int current, int total)? onProgress;
  void Function(ExecutionState state)? onStateChange;
  void Function(String line)? onPrint;

  Future<ExecutionResult> execute(Map<String, dynamic> playJson);
  void cancel();
}
```

输入是 **反序列化后的 `play` 执行体**（从完整 playbook JSON 中提取 `play` 字段）。

### 5.2 递归 Walker 实现

```dart
class _ExecScope {
  final ExecutionCtx ctx;
  final _cancelCompleter = Completer<void>();

  Future<void> execBlock(List<dynamic> instructions) async {
    for (int i = 0; i < instructions.length && !ctx.cancelled; i++) {
      final inst = instructions[i] as Map<String, dynamic>;
      await execInstruction(inst);
    }
  }

  Future<void> execInstruction(Map<String, dynamic> inst) async {
    switch (inst['type']) {
      case 'toy_call': await _execToyCall(inst); break;
      case 'wait':     await _execWait(inst);     break;
      case 'assign':   await _execAssign(inst);   break;
      case 'print':    _execPrint(inst);          break;
      case 'if':       await _execIf(inst);       break;
      case 'while':    await _execWhile(inst);    break;
      case 'repeat':   await _execRepeat(inst);   break;
      case 'break':    throw _BreakException();
    }
  }
}
```

### 5.3 Wait 实现

```dart
Future<void> _execWait(Map<String, dynamic> inst) async {
  final ms = inst['ms'] as int;
  if (ms <= 0) return;

  // 使用 Future.any 支持即时取消
  await Future.any([
    _cancelCompleter.future,
    Future.delayed(Duration(milliseconds: ms)),
  ]);
}
```

### 5.4 Repeat 实现

```dart
Future<void> _execRepeat(Map<String, dynamic> inst) async {
  final body = inst['body'] as List;

  int counter = 0;
  final int? times = inst['times'] as int?;
  final untilExpr = inst['until'] as Map<String, dynamic>?;

  do {
    try {
      await execBlock(body);
    } on _BreakException {
      break;
    }
    counter++;
    if (ctx.cancelled) break;

    // times 模式：计数终止
    if (times != null && counter >= times) break;

    // until 模式：条件满足终止
    if (untilExpr != null) {
      final cond = await evalExpr(untilExpr, ctx);
      if (_isTruthy(cond)) break;
    }

  } while (true);
}
```

---

## 6. 执行上下文与变量系统

### 6.1 ExecutionCtx

```dart
class ExecutionCtx {
  final Map<String, dynamic> vars = {};
  bool cancelled = false;
  final _cancelCompleter = Completer<void>();

  void cancel() {
    cancelled = true;
    if (!_cancelCompleter.isCompleted) {
      _cancelCompleter.complete();
    }
  }

  // 读变量：未定义返回 0（等 Lua 语义）
  dynamic getVar(String name) => vars.containsKey(name) ? vars[name] : 0;

  void setVar(String name, dynamic value) => vars[name] = value;
}
```

### 6.2 变量初始化

执行入口处：

```dart
Future<ExecutionResult> execute(Map<String, dynamic> playJson) async {
  _ctx = ExecutionCtx();

  // 初始化顶层变量
  final vars = playJson['vars'] as Map<String, dynamic>?;
  if (vars != null) {
    vars.forEach((k, v) => _ctx.setVar(k, v));
  }

  final body = playJson['body'] as List;
  await _scope.execBlock(body);
  ...
}
```

### 6.3 作用域规则（Flat 模式）

- 所有 `assign` 操作同一个 `ctx.vars` Map
- 无块级作用域，无变量遮蔽
- 未声明变量首次 `assign` 时自动创建
- 未声明变量读到时返回 `0`（等 Lua 的 nil→0 转换）

---

## 7. Cancel 与错误处理

### 7.1 取消流程

```
用户点「紧急停止」
        │
        ▼
ctx.cancel()
   ├── ctx.cancelled = true
   └── _cancelCompleter.complete()
              │
              ▼
   wait() 中的 Future.any 立即唤醒
              │
              ▼
   walker 返回，execBlock 循环检查
   ctx.cancelled → 退出循环
              │
              ▼
   顶层 catch _CancelledException
   → 调用 registry.stopAll()
   → 返回 ExecutionResult(success: false, error: "用户取消")
```

### 7.2 错误处理

| 情况 | 处理 |
|------|------|
| JSON 解析失败 | 执行前校验 schema，失败返回 error |
| toy_id 未注册 | 输出日志到 printOutput，跳过该指令继续执行 |
| toy_call 执行异常 | catch 异常，输出到 printOutput，继续执行下一条 |
| 递归栈溢出 | Dart 自带保护（playbook 深度 < 20 层，安全） |

---

## 8. Playbook 元数据格式

现有 `Playbook` 模型增加 `jsonPlay` 字段：

```dart
class Playbook {
  final String id;
  final String name;
  final int duration;           // 从 duration_sec 映射
  final List<String> steps;     // 从 steps[].desc 映射
  // final String luaScript;    // ← 删除
  final Map<String, dynamic>? jsonPlay;  // ← 新增
}
```

**迁移兼容**：存量 playbook 若无 `jsonPlay`，执行页面展示"无法执行（旧格式）"提示。后续可通过 Hermes 服务端重新生成新格式。

---

## 9. 迁移计划

### 9.1 文件变更清单

| 操作 | 文件 | 说明 |
|------|------|------|
| 🔴 删除 | `lib/services/lua/lua_executor.dart` | 整文件删除 |
| 🔴 删除 | `lib/services/lua/` 目录 | 无人用目录 |
| 🟢 新建 | `lib/services/executor/ast_types.dart` | AST 类型定义 + `fromJson()` |
| 🟢 新建 | `lib/services/executor/execution_ctx.dart` | 执行上下文 |
| 🟢 新建 | `lib/services/executor/json_play_executor.dart` | 核心 walker |
| 🟡 修改 | `lib/services/playbook_model.dart` | Playbook 实体加 `jsonPlay` 字段 |
| 🟡 修改 | `lib/pages/execution_page.dart` | 改调 `JsonPlayExecutor` |
| 🟡 修改 | `lib/services/deepseek_api.dart` | 解析 JSON AST 替代 Lua block |
| 🟡 修改 | `lib/services/playbook_import.dart` | 导入新格式 |
| 🟡 修改 | `lib/services/hermes_api.dart` | Hermes 端同步改 |

### 9.2 开发顺序

```
Phase 1: AST 类型定义 + JSON 解析器 (ast_types.dart)
         ↓
Phase 2: ExecutionCtx + evalExpr 表达式求值
         ↓
Phase 3: Async Walker 核心 (除控制流以外)
         ↓
Phase 4: 控制流指令 (if/while/repeat)
         ↓
Phase 5: Cancel 机制
         ↓
Phase 6: ExecutionPage 集成 + 存量数据迁移
         ↓
Phase 7: DeepSeek prompt 调教 + Agent Skill 编写
```

---

## 10. Agent Skill 设计要点

### 10.1 DeepSeek prompt 改造

**输入模板**：

```
你是一个情趣玩具玩法脚本作者。请根据对话历史生成一个 JSON AST 格式的玩法脚本。

## 可用的玩具
{toy_descriptions}

## JSON AST Schema
{version 2 的完整 schema 描述}

## 注意
- 所有控制流指令必须使用 JSON AST 格式
- toy_call 的 args 支持表达式
- 传感器返回值请用 assign + toy_call 表达式形式
- 输出 ```json ... ``` 代码块
```

### 10.2 Skill 内容

该 skill 应包含：

1. JSON AST 完整 schema 定义（本文档第3节）
2. 表达式系统说明（本文档第4节）
3. 玩具能力映射表（从已有 skill 迁移）
4. few-shot 示例（完整 playbook + JSON AST 对）
5. 渲染规则（prompt 模板）

---

## 11. 附录：完整示例

### 11.1 完整 Playbook JSON

```json
{
  "version": 2,
  "name": "灌肠渐进式调教",
  "toy_ids": ["enema_1", "mast_1"],
  "duration_sec": 180,
  "steps": [
    {"time_sec": 0,   "desc": "初始化，设置安全压力上限"},
    {"time_sec": 5,   "desc": "缓慢注水至 40% 压力"},
    {"time_sec": 30,  "desc": "维持压力，监测是否适应"},
    {"time_sec": 60,  "desc": "如适应则继续加压至 60%"},
    {"time_sec": 120, "desc": "配合飞机杯低频刺激"},
    {"time_sec": 150, "desc": "逐步放松"}
  ],
  "play": {
    "vars": {
      "max_pressure": 80,
      "target_pressure": 40,
      "step_size": 5,
      "counter": 0
    },
    "body": [
      { "type": "print", "msg": "=== 灌肠渐进式调教开始 ===" },
      { "type": "toy_call", "toy": "enema_1", "method": "set_speed", "args": [0] },

      { "type": "assign", "name": "current_pressure",
        "expr": { "type": "toy_call", "toy": "enema_1", "method": "read_pressure", "args": [] } },

      { "type": "print", "msg": "当前压力值读取完成" },

      { "type": "while",
        "cond": { "op": "<", "l": { "type": "var", "name": "current_pressure" }, "r": { "type": "var", "name": "target_pressure" } },
        "body": [
          { "type": "toy_call", "toy": "enema_1", "method": "set_speed", "args": [
            { "op": "+", "l": { "type": "var", "name": "current_pressure" }, "r": { "type": "num", "value": 10 } }
          ] },
          { "type": "wait", "ms": 3000 },
          { "type": "assign", "name": "current_pressure",
            "expr": { "type": "toy_call", "toy": "enema_1", "method": "read_pressure", "args": [] } }
        ]
      },

      { "type": "if",
        "cond": { "op": ">=", "l": { "type": "var", "name": "current_pressure" }, "r": { "type": "var", "name": "max_pressure" } },
        "then": [
          { "type": "toy_call", "toy": "enema_1", "method": "set_speed", "args": [0] },
          { "type": "print", "msg": "⚠ 压力超出安全上限，停止加压" }
        ],
        "else": [
          { "type": "print", "msg": "✓ 已达到目标压力，维持当前状态" },
          { "type": "wait", "ms": 30000 }
        ]
      },

      { "type": "repeat",
        "times": 3,
        "body": [
          { "type": "toy_call", "toy": "mast_1", "method": "set_speed", "args": [
            { "op": "+", "l": { "type": "var", "name": "counter" }, "r": { "type": "num", "value": 20 } }
          ] },
          { "type": "wait", "ms": 5000 },
          { "type": "toy_call", "toy": "mast_1", "method": "set_speed", "args": [0] },
          { "type": "wait", "ms": 3000 },
          { "type": "assign", "name": "counter",
            "expr": { "op": "+", "l": { "type": "var", "name": "counter" }, "r": { "type": "num", "value": 1 } } }
        ]
      },

      { "type": "toy_call", "toy": "enema_1", "method": "set_speed", "args": [0] },
      { "type": "toy_call", "toy": "mast_1", "method": "set_speed", "args": [0] },
      { "type": "print", "msg": "=== 玩法结束 ===" }
    ]
  }
}
```

### 11.2 对应模板的 LLM 回复示例

```
我将为您生成一个灌肠渐进式调教的玩法脚本：

```json
{
  "version": 2,
  "name": "灌肠渐进式调教",
  "toy_ids": ["enema_1", "mast_1"],
  "duration_sec": 180,
  ...
}
```

**步骤说明：**
1. 第一步：初始化，设置目标压力 40
2. 第二步：循环加压，每次增加 10%
3. 第三步：到达目标后维持 30 秒
4. 第四步：配合飞机杯低频刺激
5. 第五步：停止所有玩具
```
