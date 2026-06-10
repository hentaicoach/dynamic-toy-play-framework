enum ToyType {
  lock,
  enema,
  ems,
  masturbator,
  egg,
  unknown;

  String get displayName {
    switch (this) {
      case ToyType.lock:
        return '电子锁';
      case ToyType.enema:
        return '灌肠器';
      case ToyType.ems:
        return '电击器';
      case ToyType.masturbator:
        return '飞机杯';
      case ToyType.egg:
        return '跳蛋';
      case ToyType.unknown:
        return '未知';
    }
  }

  String get icon {
    switch (this) {
      case ToyType.lock:
        return '🔒';
      case ToyType.enema:
        return '💧';
      case ToyType.ems:
        return '⚡';
      case ToyType.masturbator:
        return '🌀';
      case ToyType.egg:
        return '🥚';
      case ToyType.unknown:
        return '❓';
    }
  }
}

class Toy {
  final String id;
  final ToyType type;
  final String name;
  final bool isConnected;
  final Map<String, String> apiFunctions; // 函数名 → 描述

  const Toy({
    required this.id,
    required this.type,
    required this.name,
    this.isConnected = true,
    this.apiFunctions = const {},
  });

  Toy copyWith({bool? isConnected}) {
    return Toy(
      id: id,
      type: type,
      name: name,
      isConnected: isConnected ?? this.isConnected,
      apiFunctions: apiFunctions,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'name': name,
      'api': apiFunctions,
    };
  }
}
