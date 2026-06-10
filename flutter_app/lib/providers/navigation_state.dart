import 'package:flutter/foundation.dart';

/// 全局导航状态
///
/// 用于跨 tab 切换，例如设计页生成玩法后自动跳转到玩法 tab 预览
class NavigationState extends ChangeNotifier {
  int _tabIndex = 2; // 默认定位到"设计" tab

  int get tabIndex => _tabIndex;

  void switchToTab(int index) {
    if (_tabIndex != index) {
      _tabIndex = index;
      notifyListeners();
    }
  }
}
