class PlaybookStep {
  final String time;
  final String action;

  const PlaybookStep({required this.time, required this.action});

  factory PlaybookStep.fromJson(Map<String, dynamic> json) {
    return PlaybookStep(
      time: json['time'] as String? ?? '',
      action: json['action'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'time': time, 'action': action};
}

class PlaybookExplanation {
  final String name;
  final int durationSeconds;
  final List<PlaybookStep> steps;

  const PlaybookExplanation({
    required this.name,
    required this.durationSeconds,
    required this.steps,
  });

  factory PlaybookExplanation.fromJson(Map<String, dynamic> json) {
    final stepsRaw = json['steps'] as List<dynamic>? ?? [];
    return PlaybookExplanation(
      name: json['name'] as String? ?? json['playbook_name'] as String? ?? '',
      durationSeconds: json['duration_seconds'] as int? ?? 0,
      steps: stepsRaw
          .map((e) => PlaybookStep.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'duration_seconds': durationSeconds,
        'steps': steps.map((s) => s.toJson()).toList(),
      };
}

class Playbook {
  final String id;
  final String name;
  final String luaScript;
  final String? jsonPlay;       // JSON AST（新增，替换 luaScript 的过渡）
  final PlaybookExplanation explanation;
  final DateTime createdAt;
  final List<String> toyIds;

  const Playbook({
    required this.id,
    required this.name,
    required this.luaScript,
    this.jsonPlay,
    required this.explanation,
    required this.createdAt,
    this.toyIds = const [],
  });

  String get durationDisplay {
    final secs = explanation.durationSeconds;
    if (secs < 60) return '${secs}s';
    final minutes = secs ~/ 60;
    final seconds = secs % 60;
    return seconds > 0 ? '${minutes}m${seconds}s' : '${minutes}m';
  }

  factory Playbook.fromJson(Map<String, dynamic> json) {
    return Playbook(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '未命名玩法',
      luaScript: json['lua_script'] as String? ?? json['luaScript'] as String? ?? '',
      explanation: PlaybookExplanation.fromJson(
        json['explanation'] as Map<String, dynamic>? ?? {},
      ),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      toyIds: (json['toy_ids'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lua_script': luaScript,
        'explanation': explanation.toJson(),
        'created_at': createdAt.toIso8601String(),
        'toy_ids': toyIds,
      };
}
