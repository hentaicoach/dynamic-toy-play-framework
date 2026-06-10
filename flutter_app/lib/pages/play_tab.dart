import 'package:flutter/material.dart';
import '../models/playbook.dart';
import 'library_page.dart';
import 'preview_page.dart';
import 'execution_page.dart';

/// 玩法管理 tab 的内嵌导航容器
///
/// 使用栈式状态管理（而非 Navigator），在 tab 内部实现玩法库→预览→执行的页面层级
class PlayTab extends StatefulWidget {
  const PlayTab({super.key});

  /// 外部可通过 GlobalKey 调用来从其他 tab 跳转到预览
  static final GlobalKey<PlayTabState> globalKey = GlobalKey<PlayTabState>();

  @override
  PlayTabState createState() => PlayTabState();
}

class PlayTabState extends State<PlayTab> {
  final List<_PlayRoute> _stack = [_PlayRoute('/')];

  String get currentRoute => _stack.last.route;
  bool get canPop => _stack.length > 1;

  void push(String route, {dynamic arguments}) {
    setState(() => _stack.add(_PlayRoute(route, arguments: arguments)));
  }

  void pop() {
    if (_stack.length > 1) {
      setState(() => _stack.removeLast());
    }
  }

  void popToRoot() {
    setState(() => _stack.removeRange(1, _stack.length));
  }

  /// 切换到指定玩法并预览（从外部调用，如设计对话页）
  void previewPlaybook(Playbook playbook) {
    setState(() {
      _stack
        ..clear()
        ..add(_PlayRoute('/'))
        ..add(_PlayRoute('/preview', arguments: playbook.id));
    });
  }

  @override
  Widget build(BuildContext context) {
    final current = _stack.last;

    switch (current.route) {
      case '/preview':
        return PreviewPage(
          playbookId: current.arguments as String?,
          onBack: pop,
          onExecute: (id) => push('/execution', arguments: id),
        );
      case '/execution':
        return ExecutionPage(
          playbookId: current.arguments as String?,
          onBack: pop,
          onFinish: popToRoot,
        );
      default:
        return LibraryPage(
          onPreview: (id) => push('/preview', arguments: id),
        );
    }
  }
}

class _PlayRoute {
  final String route;
  final dynamic arguments;
  const _PlayRoute(this.route, {this.arguments});
}
