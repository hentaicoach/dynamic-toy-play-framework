import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/playbook.dart';

/// 玩法方案本地持久化服务
///
/// 使用 SharedPreferences 存储 JSON 序列化的 Playbook 列表。
/// 每次写操作后立即持久化，保证数据不丢失。
class PlaybookStorageService {
  static const String _storageKey = 'playbooks_cache';

  /// 从本地存储加载所有玩法方案
  Future<List<Playbook>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Playbook.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// 保存单个玩法方案（追加到列表开头，去重）
  Future<void> save(Playbook playbook) async {
    final list = await loadAll();
    list.removeWhere((p) => p.id == playbook.id);
    list.insert(0, playbook);
    await _persist(list);
  }

  /// 批量保存（替换整个列表）
  Future<void> saveAll(List<Playbook> playbooks) async {
    await _persist(playbooks);
  }

  /// 删除单个玩法方案
  Future<void> delete(String id) async {
    final list = await loadAll();
    list.removeWhere((p) => p.id == id);
    await _persist(list);
  }

  /// 清空所有玩法方案
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  /// 持久化整个列表
  Future<void> _persist(List<Playbook> playbooks) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(playbooks.map((p) => p.toJson()).toList());
    await prefs.setString(_storageKey, raw);
  }
}
