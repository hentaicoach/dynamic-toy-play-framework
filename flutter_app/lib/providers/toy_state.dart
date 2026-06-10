import 'package:flutter/foundation.dart';
import '../models/toy.dart';

/// 全局玩具连接状态
class ToyState extends ChangeNotifier {
  final List<Toy> _connectedToys = [];

  List<Toy> get connectedToys => List.unmodifiable(_connectedToys);

  bool get hasToys => _connectedToys.isNotEmpty;

  int get count => _connectedToys.length;

  void addToy(Toy toy) {
    _connectedToys.add(toy);
    notifyListeners();
  }

  void removeToy(String id) {
    _connectedToys.removeWhere((t) => t.id == id);
    notifyListeners();
  }

  /// 批量替换已连接列表
  void replaceAll(List<Toy> toys) {
    _connectedToys
      ..clear()
      ..addAll(toys);
    notifyListeners();
  }

  Toy? getToy(String id) {
    try {
      return _connectedToys.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  void clear() {
    _connectedToys.clear();
    notifyListeners();
  }
}
