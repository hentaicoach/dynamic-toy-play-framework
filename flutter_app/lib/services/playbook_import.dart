import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/playbook.dart';

/// 从服务器导入玩法方案
class PlaybookImportService {
  final String baseUrl;

  PlaybookImportService({this.baseUrl = 'http://10.0.2.2:8765'});

  /// 从服务端 /api/playbooks 获取所有注册玩法
  Future<List<Playbook>> fetchFromServer() async {
    final uri = Uri.parse('$baseUrl/api/playbooks');
    final resp = await http.get(uri).timeout(const Duration(seconds: 10));

    if (resp.statusCode != 200) {
      throw Exception('服务器返回 ${resp.statusCode}');
    }

    final list = jsonDecode(resp.body) as List<dynamic>;
    final result = <Playbook>[];

    for (final raw in list) {
      final item = raw as Map<String, dynamic>;

      final luaScript = item['lua_script'] as String? ?? '';
      final toys = (item['toys'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];

      final steps = _parseStepsFromLua(luaScript);
      final durationStr = item['duration'] as String? ?? '';
      final docMd = item['doc_markdown'] as String? ?? '';

      // 如果有 doc_markdown，从里面解析步骤更准
      final finalSteps = docMd.isNotEmpty
          ? _parseStepsFromDoc(docMd)
          : steps;

      final pb = Playbook(
        id: item['id'] as String? ?? '',
        name: item['name'] as String? ?? '未命名玩法',
        luaScript: luaScript,
        explanation: PlaybookExplanation(
          name: item['name'] as String? ?? '未命名玩法',
          durationSeconds: _parseDuration(durationStr),
          steps: finalSteps,
        ),
        createdAt: DateTime.tryParse(item['created'] as String? ?? '') ??
            DateTime.now(),
        toyIds: toys,
      );

      result.add(pb);
    }

    return result;
  }

  /// 从 Lua 脚本注释中提取阶段步骤
  List<PlaybookStep> _parseStepsFromLua(String lua) {
    final steps = <PlaybookStep>[];

    for (final line in lua.split('\n')) {
      final trimmed = line.trim();
      // 匹配 "阶段①：绑缚上锁 ============"
      final stageMatch = RegExp(
        r'阶段[①②③④⑤⑥⑦⑧⑨⑩][：:]\s*(.*?)\s*(?:[=\-]+)?\s*$',
      ).firstMatch(trimmed);
      if (stageMatch != null) {
        steps.add(PlaybookStep(
          time: '阶段${steps.length + 1}',
          action: stageMatch.group(1)?.trim() ?? '',
        ));
      }
    }

    if (steps.isNotEmpty) return steps;

    // 回退：从注释中的阶段描述提取
    for (final line in lua.split('\n')) {
      final trimmed = line.trim();
      final printMatch = RegExp(
        r'print\("\[阶段\d+\]\s*(.+?)"\)',
      ).firstMatch(trimmed);
      if (printMatch != null) {
        steps.add(PlaybookStep(
          time: '阶段${steps.length + 1}',
          action: printMatch.group(1)?.trim() ?? '',
        ));
      }
    }

    if (steps.isEmpty) {
      steps.add(const PlaybookStep(time: '开始', action: '执行 Lua 脚本'));
    }

    return steps;
  }

  /// 从 doc_markdown 的步骤解读区域解析更详细的步骤
  List<PlaybookStep> _parseStepsFromDoc(String doc) {
    final steps = <PlaybookStep>[];

    // 在 ``` 代码块外的内容中找步骤
    final inCodeBlock = RegExp(r'```');
    bool inBlock = false;
    final bodyLines = <String>[];

    for (final line in doc.split('\n')) {
      if (inCodeBlock.hasMatch(line.trim())) {
        inBlock = !inBlock;
        continue;
      }
      if (inBlock) continue;
      bodyLines.add(line);
    }

    final bodyText = bodyLines.join('\n');

    // 找步骤解读块（通常在 ``` 之间的纯文本部分）
    // 格式: ① 0-5秒   动作描述
    final stepPattern = RegExp(
      r'[①②③④⑤⑥⑦⑧⑨⑩]\s*'
      r'(\S[\d\s\-~秒分]*)\s{2,}'
      r'(.+)',
    );
    for (final m in stepPattern.allMatches(bodyText)) {
      steps.add(PlaybookStep(
        time: m.group(1)?.trim() ?? '',
        action: m.group(2)?.trim() ?? '',
      ));
    }

    // 如果 doc 中没找到，回退到 Lua 解析
    if (steps.isEmpty) {
      return _parseStepsFromLua(doc); // doc 里也可能有 Lua
    }

    return steps;
  }

  /// 解析时长字符串为秒数
  int _parseDuration(String str) {
    // 处理 "约 90 秒 + 玩家等待时间"
    final clean = str.replaceAll(RegExp(r'[^\d]'), ' ').trim();
    final nums = clean.split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
    final firstNum = nums.firstWhere(
      (s) => int.tryParse(s) != null,
      orElse: () => '0',
    );
    final num = int.tryParse(firstNum) ?? 0;

    if (str.contains('分') && !str.contains('秒')) return num * 60;
    return num;
  }
}
