import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/chat_message.dart';
import '../models/playbook.dart';
import '../models/toy.dart';
import 'package:yokonex_play/config/constants.dart';

/// 直接调 DeepSeek API 玩法设计服务
class DeepseekApiService extends ChangeNotifier {
  final List<ChatMessage> _messages = [];
  final List<Map<String, String>> _apiMessages = [];
  PlaybookResult? _lastPlaybook;
  String? _lastError;
  bool _isLoading = false;

  String _apiKey = '';
  String _baseUrl = 'https://api.deepseek.com/v1';
  String _model = 'deepseek-v4-flash';

  // ── Getters ──
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  PlaybookResult? get lastPlaybook => _lastPlaybook;
  String? get lastError => _lastError;
  bool get isLoading => _isLoading;

  /// 配置 API
  void configure({
    required String apiKey,
    String baseUrl = 'https://api.deepseek.com/v1',
    String model = 'deepseek-v4-flash',
  }) {
    _apiKey = apiKey;
    _baseUrl = baseUrl;
    _model = model;
  }

  bool get isConfigured => _apiKey.isNotEmpty;

  // ── 对话 ──

  void start(List<Toy> toys) {
    _messages.clear();
    _apiMessages.clear();
    _lastPlaybook = null;
    _lastError = null;

    final systemPrompt = _buildSystemPrompt(toys);
    _apiMessages.add({'role': 'system', 'content': systemPrompt});
    sendMessage('请帮我设计一个玩法');
  }

  Future<void> sendMessage(String text) async {
    if (_apiKey.isEmpty) {
      _lastError = '未配置 API Key';
      notifyListeners();
      return;
    }

    _messages.add(ChatMessage(role: 'user', content: text));
    _apiMessages.add({'role': 'user', 'content': text});
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _callDeepseek(_apiMessages);
      _isLoading = false;

      if (response == null) {
        _lastError = 'API 无响应';
        notifyListeners();
        return;
      }

      _apiMessages.add({'role': 'assistant', 'content': response});

      if (_isPlaybookResponse(response)) {
        final parsed = _parsePlaybook(response);
        _lastPlaybook = parsed;
        _messages.add(ChatMessage(
          role: 'assistant',
          content: '🔥 玩法方案已生成！点击下方按钮预览 👇',
          hasPreview: true,
        ));
      } else {
        _messages.add(ChatMessage(role: 'assistant', content: response));
      }

      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _lastError = 'API 调用异常: $e';
      _messages.add(ChatMessage(role: 'assistant', content: '❌ $_lastError'));
      notifyListeners();
    }
  }

  void clear() {
    _messages.clear();
    _apiMessages.clear();
    _lastPlaybook = null;
    _lastError = null;
    _isLoading = false;
    notifyListeners();
  }

  // ── 内部 ──

  String _buildSystemPrompt(List<Toy> toys) {
    final buf = StringBuffer();
    buf.writeln('你是一个情趣玩具玩法设计助手。通过多轮对话帮助用户设计玩法，最终生成 JSON AST 格式的结构化脚本。');
    buf.writeln('');
    buf.writeln('## 行为规则');
    buf.writeln('1. **一次只问一个问题**，附带推荐选项（3-4个）+ 开放式入口');
    buf.writeln('2. **每个问题必须有推荐选项**（"→ 推荐：XXX"），让用户快速决策');
    buf.writeln('3. **根据已收集的信息动态跳问答**，不要问已经明确或无关的问题');
    buf.writeln('4. **用户回答很明确时可以跳过一个或多个 Phase**，直接进入生成');
    buf.writeln('5. **不要在用户还没回答时一下子问一堆**');
    buf.writeln('6. **迭代调整时不重新问全部问题**，只调整对应参数');
    buf.writeln('7. **迭代不超过 5 轮**，超过建议"基础定型后再微调"');
    buf.writeln('');

    if (toys.isNotEmpty) {
      buf.writeln('## 可用的玩具（生成的 JSON AST 必须使用以下确切的 toy ID，不得自创）');
      buf.writeln('');
      for (final t in toys) {
        buf.writeln(t.id + ' (' + t.name + ')');
        if (t.apiFunctions.isNotEmpty) {
          for (final entry in t.apiFunctions.entries) {
            buf.writeln('  - ' + entry.key + ' — ' + entry.value);
          }
        }
        buf.writeln('');
      }
      buf.writeln('【铁律】玩具 ID 必须与列表一致，不能自创。');
      buf.writeln('方法名必须使用具体的驱动方法名（如 rate、fill、read_pressure），不能用 set_intensity 等通用词。');
      buf.writeln('');
    }

    buf.writeln('## 对话流程');
    buf.writeln('');
    buf.writeln('### Phase 0：开场');
    buf.writeln('打招呼 + 展示已连接玩具清单，然后问第一个问题。');
    buf.writeln('如果无玩具信息，改成问用户有哪些玩具。');
    buf.writeln('');
    buf.writeln('### Phase 1：基础需求（选玩具 → 时长 → 强度曲线）');
    buf.writeln('- Q1: 选择玩具（单玩具可跳过）');
    buf.writeln('- Q2: 总时长（推荐3-5分钟）');
    buf.writeln('- Q3: 整体强度曲线（推荐渐进式）');
    buf.writeln('');
    buf.writeln('### Phase 2：节奏与感觉');
    buf.writeln('- Q4: 节奏模式（推荐混合节奏）');
    buf.writeln('- Q5: 感觉偏好（根据已连接的玩具类型动态调整问题措辞）');
    buf.writeln('- Q6: 特殊需求（可选）');
    buf.writeln('');
    buf.writeln('### Phase 3：玩具协调');
    buf.writeln('- 1个玩具 → 跳过');
    buf.writeln('- 2个玩具 → 问配合方式（推荐交替错峰）');
    buf.writeln('- 3+个玩具 → 问整体结构（推荐分阶段推进）');
    buf.writeln('');
    buf.writeln('### Phase 4：生成方案');
    buf.writeln('当信息收集充分后，按最终输出格式生成 JSON AST 方案。');
    buf.writeln('');
    buf.writeln('### Phase 5：迭代调整');
    buf.writeln('用户说"降30%" → 所有数值参数乘以 0.7');
    buf.writeln('用户说"提前/延后" → 调整对应 wait 的时间');
    buf.writeln('用户说"可以了/定稿" → 输出最终格式');
    buf.writeln('');
    buf.writeln('## 参数映射规则');
    buf.writeln('| 用户描述词 | 强度映射 | 节奏映射 |');
    buf.writeln('|-----------|---------|---------|');
    buf.writeln('| 温柔/轻柔/轻轻 | 10-30% | 10-30% |');
    buf.writeln('| 中等/适中 | 40-60% | 40-60% |');
    buf.writeln('| 强烈/重口/猛 | 70-90% | 70-90% |');
    buf.writeln('| 满/全开/最 | 95-100% | 95-100% |');
    buf.writeln('| 脉冲/间断 | 交替 0↔目标值 | N/A |');
    buf.writeln('| 渐进/慢慢来 | 每阶段+20% | 每阶段+15% |');
    buf.writeln('');
    buf.writeln('## 玩法名称生成规则');
    buf.writeln('根据玩具组合和风格自动生成中文名（2-5字）：');
    buf.writeln('- 震动棒+电击器 → 潮汐协奏 / 脉冲共鸣');
    buf.writeln('- 灌肠机+电击器 → 充盈电击 / 潮涌震颤');
    buf.writeln('- 灌肠机+飞机杯+电击器+锁 → 赎罪倒计时 / 极限回响');
    buf.writeln('- 多玩具全套装 → 潮汐三重奏 / 极限回响');
    buf.writeln('- 单玩具温柔 → 轻语 / 渐入佳境');
    buf.writeln('- 单玩具强烈 → 狂想曲 / 极速脉搏');
    buf.writeln('');
    buf.writeln('## 安全规则');
    buf.writeln('1. 生成的 JSON AST 必须包含安全机制——最后必须有停止所有玩具的 toy_call');
    buf.writeln('2. 不要让 wait 时间太长（建议最长 30 秒一段），长阶段拆成多个子阶段');
    buf.writeln('3. 控制强度逐步递增，不要直接满强度');
    buf.writeln('4. play.body 指令序列长度不超过 200 条');
    buf.writeln('');
    buf.writeln('## JSON AST Schema');
    buf.writeln('');
    buf.writeln('### 顶层结构');
    buf.writeln('```json');
    buf.writeln('{');
    buf.writeln('  "version": 2,');
    buf.writeln('  "name": "玩法名称（2-5字）",');
    buf.writeln('  "toy_ids": ["玩具ID"],');
    buf.writeln('  "duration_sec": 180,');
    buf.writeln('  "steps": [{"time_sec": 0, "desc": "步骤描述"}],');
    buf.writeln('  "play": {');
    buf.writeln('    "vars": {"变量名": 初始值},');
    buf.writeln('    "body": [指令序列]');
    buf.writeln('  }');
    buf.writeln('}');
    buf.writeln('```');
    buf.writeln('');
    buf.writeln('### 指令类型');
    buf.writeln('');
    buf.writeln('**toy_call**: {"type":"toy_call","toy":"enema_1","method":"fill","args":[3]}');
    buf.writeln('**wait**: {"type":"wait","ms":2000}（ms 整数）');
    buf.writeln('**assign**: {"type":"assign","name":"x","expr":{表达式}}');
    buf.writeln('**print**: {"type":"print","msg":"文本"}');
    buf.writeln('**if**: {"type":"if","cond":{表达式},"then":[指令],"else":[指令]}（else可选）');
    buf.writeln('**while**: {"type":"while","cond":{表达式},"body":[指令]}');
    buf.writeln('**repeat**: {"type":"repeat","body":[指令],"times":5} 或 "until":{条件}（互斥）');
    buf.writeln('**break**: {"type":"break"}');
    buf.writeln('');
    buf.writeln('### 表达式类型');
    buf.writeln('- 数值: {"type":"num","value":42}');
    buf.writeln('- 变量: {"type":"var","name":"pressure"}');
    buf.writeln('- 二元: {"type":"binop","op":"+","l":{左},"r":{右}}');
    buf.writeln('  操作符: + - * / % ^ == ~= > < >= <= and or ..');
    buf.writeln('- 一元: {"type":"unop","op":"not","x":{表达式}}');
    buf.writeln('  操作符: not - #');
    buf.writeln('- toy_call 作表达式（有返回值时）: 同玩具调用格式, 嵌套在 assign.expr 中');
    buf.writeln('');
    buf.writeln('## 最终输出格式（严格规定 — 必须完全遵守）');
    buf.writeln('```markdown');
    buf.writeln('🔥【玩法名称】');
    buf.writeln('');
    buf.writeln('```json');
    buf.writeln('{完整的 JSON AST}');
    buf.writeln('```');
    buf.writeln('');
    buf.writeln('⏱ 总时长：约 XXX 秒');
    buf.writeln('');
    buf.writeln('① 0s - XXs  [玩具]动作描述');
    buf.writeln('② XXs - XXs [玩具]动作描述');
    buf.writeln('');
    buf.writeln('### 格式铁律');
    buf.writeln('');
    buf.writeln('1. **JSON AST 必须是合法的 JSON**，输出在单独的 ```json 代码块中');
    buf.writeln('2. **玩具 ID 必须与已连接的 toys 列表一致**，不能自创');
    buf.writeln('3. **方法名必须是具体的驱动方法名**（如 rate 不是 set_intensity）');
    buf.writeln('4. **steps[] 中的 desc 必须完整可读**，直接用作 UI 步骤描述');
    buf.writeln('5. **所有 wait 的 ms 值加总应大致等于 duration_sec**');
    buf.writeln('6. **最后必须有停止所有玩具的 toy_call 指令**');

    return buf.toString();
  }
  Future<String?> _callDeepseek(List<Map<String, String>> messages) async {
    final uri = Uri.parse('$_baseUrl/chat/completions');
    final payload = {
      'model': _model,
      'messages': messages,
      'max_tokens': 8192,
      'temperature': 0.7,
    };

    Log.d('[DeepseekAPI] Calling $_model, messages=${messages.length}');

    final resp = await http
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 600));

    if (resp.statusCode != 200) {
      Log.d('[DeepseekAPI] HTTP ${resp.statusCode}: ${resp.body}');
      _lastError = 'API 错误 ${resp.statusCode}';
      return null;
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final choices = data['choices'] as List? ?? [];
    if (choices.isEmpty) return null;

    final content = (choices[0] as Map)['message']?['content'] as String?;
    return content;
  }

  /// 判断是否为最终方案回复
  bool _isPlaybookResponse(String text) {
    // 检测 JSON 代码块或 JSON 根特征
    return text.contains('```json') ||
        text.contains('"version": 2') ||
        (text.contains('"play"') && text.contains('"body"'));
  }
  /// 解析最终方案 — 多级策略
  PlaybookResult _parsePlaybook(String text) {
    final jsonStr = _extractJsonAst(text);
    final name = _extractPlaybookName(text, jsonStr);
    final jsonPlay = _parseJsonPlay(jsonStr);

    final duration = jsonPlay['duration_sec'] ?? 0;

    // 解析 steps
    final steps = <PlaybookStep>[];
    final rawSteps = jsonPlay['steps'] as List<dynamic>? ?? [];
    for (final s in rawSteps) {
      steps.add(PlaybookStep(
        time: '${s['time_sec']}s',
        action: s['desc'] ?? '',
      ));
    }

    Log.d('[DeepseekAPI] Parsed JSON playbook: name=$name'
        ' duration=$duration steps=${steps.length}');

    return PlaybookResult(
      playbookName: name,
      playScript: jsonStr,
      explanation: PlaybookExplanation(
        name: name,
        durationSeconds: duration is int ? duration : 0,
        steps: steps,
      ),
    );
  }

  /// 提取 JSON AST 字符串
  String _extractJsonAst(String text) {
    // 策略1: ```json 代码块
    final codeBlock = RegExp(
      r'```json\s*\n([\s\S]*?)```',
      caseSensitive: false,
    ).firstMatch(text);
    if (codeBlock != null) {
      final json = codeBlock.group(1)!.trim();
      // 验证是 JSON 对象
      if (json.startsWith('{')) return json;
    }

    // 策略2: 直接从 "version": 2 开始找
    final startIdx = text.indexOf('"version":');
    if (startIdx >= 0) {
      // 从 { 开始找
      final braceStart = text.lastIndexOf('{', startIdx);
      if (braceStart >= 0) {
        // 用括号匹配找结束
        int depth = 0;
        for (int i = braceStart; i < text.length; i++) {
          if (text[i] == '{') depth++;
          if (text[i] == '}') depth--;
          if (depth == 0) {
            return text.substring(braceStart, i + 1);
          }
        }
      }
    }

    Log.d('[DeepseekAPI] WARNING: Failed to extract JSON AST');
    return '{}';
  }

  /// 解析 JSON AST 为 Map
  Map<String, dynamic> _parseJsonPlay(String jsonStr) {
    if (jsonStr.isEmpty || jsonStr == '{}') return {};
    try {
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      Log.d('[DeepseekAPI] JSON parse error: $e');
      return {};
    }
  }
  /// 提取玩法名称
  String _extractPlaybookName(String text, String jsonStr) {
    // 1. 从 JSON AST 中读 name 字段
    if (jsonStr.isNotEmpty && jsonStr != '{}') {
      try {
        final data = jsonDecode(jsonStr);
        final name = data['name'] as String?;
        if (name != null && name.isNotEmpty && name.length <= 20) return name;
      } catch (_) {}
    }

    // 2. 从 🔥【名称】格式提取
    final bracketMatch = RegExp(r'[🔥]?【(.+?)】').firstMatch(text);
    if (bracketMatch != null) {
      final name = bracketMatch.group(1)!.trim();
      if (name.isNotEmpty && name.length <= 20) return name;
    }

    // 3. 兜底：从玩具 ID 自动生成
    return _autoGenerateName(jsonStr);
  }
  /// 根据 JSON AST 中的玩具 ID 自动生成玩法名称
  String _autoGenerateName(String jsonStr) {
    if (jsonStr.isEmpty || jsonStr == '{}') return '自定义玩法';

    // 从 JSON 中提取 toy_ids
    try {
      final data = jsonDecode(jsonStr);
      final ids = (data['toy_ids'] as List<dynamic>?)?.cast<String>() ?? [];
      if (ids.isEmpty) {
        // 从 body 中嗅探
        final bodyStr = jsonEncode(data['play']?['body'] ?? []);
        final idPattern = RegExp(r'"toy":\s*"([^"]+)"');
        for (final m in idPattern.allMatches(bodyStr)) {
          ids.add(m.group(1)!);
        }
      }

      if (ids.isEmpty) return '自定义玩法';

      final uniqueIds = ids.toSet().toList();
      bool has(String pattern) =>
          uniqueIds.any((id) => id.toLowerCase().contains(pattern));

      final hasEms = has('ems') || has('shock');
      final hasEnema = has('enema') || has('pump') || has('plug');
      final hasVibe = has('vibe') || has('mast') || has('vibrator') || has('cup');
      final hasLock = has('lock');

      if (hasEms && hasEnema && hasVibe && hasLock) return '极限回响';
      if (hasEms && hasEnema && hasVibe) return '潮汐三重奏';
      if (hasEms && hasEnema) return '充盈电击';
      if (hasEms && hasVibe) return '脉冲共鸣';
      if (hasVibe && hasEnema) return '潮涌震颤';
      if (hasLock && (hasEms || hasVibe)) return '枷锁回响';
      if (hasEms || hasVibe) return '渐入佳境';
      if (hasEnema) return '充盈';

      return '${uniqueIds.length}机联动';
    } catch (_) {
      return '自定义玩法';
    }
  }
  /// 提取步骤 — 从 JSON AST 中读取 steps 数组或从正文回退解析
  List<PlaybookStep> _extractSteps(String fullText, String jsonStr) {
    // 策略1: 从 JSON AST 的 steps 数组读取
    if (jsonStr.isNotEmpty && jsonStr != '{}') {
      try {
        final data = jsonDecode(jsonStr);
        final rawSteps = data['steps'] as List<dynamic>? ?? [];
        if (rawSteps.isNotEmpty) {
          return rawSteps.map((s) => PlaybookStep(
            time: '${s['time_sec']}s',
            action: s['desc'] ?? '',
          )).toList();
        }
      } catch (_) {}
    }

    // 策略2: 回退到从正文提取（不带 Lua 过滤）
    final steps = <PlaybookStep>[];
    final bodyText = fullText.replaceAll(jsonStr, '');

    // Unicode 圆圈数字编号
    final unicodePattern = RegExp(
      r'[①②③④⑤⑥⑦⑧⑨⑩]\s*'
      r'(\d+[\d\s\-~]*\s*秒?)\s+'
      r'(.+?)(?=\n[①②③④⑤⑥⑦⑧⑨⑩]|\Z)',
    );
    for (final m in unicodePattern.allMatches(bodyText)) {
      steps.add(PlaybookStep(
        time: m.group(1)?.trim() ?? '',
        action: m.group(2)?.trim() ?? '',
      ));
    }

    return steps;
  }
  /// 提取时长（秒）— 从 JSON AST 中读取 duration_sec 或从正文回退
  int _extractDuration(String text) {
    // 策略1: 从 JSON AST 读 duration_sec
    final jsonBlock = RegExp(
      r'```json\s*\n([\s\S]*?)```',
      caseSensitive: false,
    ).firstMatch(text);
    if (jsonBlock != null) {
      try {
        final data = jsonDecode(jsonBlock.group(1)!);
        final dur = data['duration_sec'] as int?;
        if (dur != null && dur > 0 && dur < 3600) return dur;
      } catch (_) {}
    }

    // 策略2: 从正文中的 总时长 行提取
    final patterns = [
      RegExp(r'总时长[：:]\s*约?\s*(\d+)\s*秒'),
      RegExp(r'时长[：:]\s*约?\s*(\d+)\s*秒'),
      RegExp(r'总时长[：:]\s*约?\s*(\d+)'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(text);
      if (m != null) {
        final val = int.tryParse(m.group(1) ?? '');
        if (val != null && val > 0 && val < 3600) return val;
      }
    }

    return 0;
  }
  @override
  void dispose() {
    super.dispose();
  }
}

/// 玩法方案结果
class PlaybookResult {
  final String playbookName;
  final String playScript;  // JSON AST 字符串
  final PlaybookExplanation explanation;

  PlaybookResult({
    required this.playbookName,
    required this.playScript,
    required this.explanation,
  });
}
