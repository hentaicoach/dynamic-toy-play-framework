import 'package:flutter/foundation.dart';
import '../models/playbook.dart';
import '../services/playbook_storage.dart';

/// 全局玩法状态
///
/// 管理所有玩法方案的增删改查，自动同步到本地持久化存储。
/// 启动时从 SharedPreferences 加载已有数据。
class PlaybookState extends ChangeNotifier {
  final PlaybookStorageService _storage = PlaybookStorageService();
  final List<Playbook> _playbooks = [];
  bool _loaded = false;

  List<Playbook> get playbooks => List.unmodifiable(_playbooks);
  int get count => _playbooks.length;
  bool get isLoaded => _loaded;

  /// 从本地存储加载数据（App 启动时调用）
  Future<void> loadFromStorage() async {
    if (_loaded) return;
    final stored = await _storage.loadAll();
    _playbooks
      ..clear()
      ..addAll(stored);
    _loaded = true;
    notifyListeners();
  }

  /// 添加新的玩法方案（加到列表最前，自动保存）
  Future<void> addPlaybook(Playbook pb) async {
    _playbooks.insert(0, pb);
    await _storage.save(pb);
    notifyListeners();
  }

  /// 批量导入（来自服务器）
  Future<void> importAll(List<Playbook> playbooks) async {
    for (final pb in playbooks) {
      _playbooks.removeWhere((p) => p.id == pb.id);
      _playbooks.add(pb);
    }
    await _storage.saveAll(_playbooks);
    notifyListeners();
  }

  /// 获取最近生成的一个玩法
  Playbook? get latest =>
      _playbooks.isNotEmpty ? _playbooks.first : null;

  /// 按 ID 查找
  Playbook? getById(String id) {
    try {
      return _playbooks.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 删除
  Future<void> removePlaybook(String id) async {
    _playbooks.removeWhere((p) => p.id == id);
    await _storage.delete(id);
    notifyListeners();
  }

  /// 清空
  Future<void> clear() async {
    _playbooks.clear();
    await _storage.clear();
    notifyListeners();
  }
}
