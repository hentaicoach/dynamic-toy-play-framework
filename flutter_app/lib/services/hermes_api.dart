import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/constants.dart';
import '../models/chat_message.dart';
import '../models/playbook.dart';
import '../models/toy.dart';
import 'deepseek_api.dart';
import 'package:yokonex_play/config/constants.dart';

/// WebSocket 连接状态
enum WsConnectionState { disconnected, connecting, connected, error }

/// 服务端推送的玩法方案
// 使用 deepseek_api.dart 中的 PlaybookResult

/// Hermes API WebSocket 客户端
///
/// 连接本地 Hermes Toy API 服务，实现多轮对话设计玩法。
class HermesApiService extends ChangeNotifier {
  WebSocket? _ws;
  Timer? _reconnectTimer;
  bool _disposed = false;

  // ── 状态 ──
  WsConnectionState _connectionState = WsConnectionState.disconnected;
  final List<ChatMessage> _messages = [];
  PlaybookResult? _lastPlaybook;
  String? _lastError;

  // ── Getters ──
  WsConnectionState get connectionState => _connectionState;
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  PlaybookResult? get lastPlaybook => _lastPlaybook;
  String? get lastError => _lastError;
  bool get isConnected => _connectionState == WsConnectionState.connected;

  // ── 连接 ──

  /// 建立 WebSocket 连接
  Future<void> connect({
    String host = AppConstants.hermesHost,
    int port = AppConstants.hermesPort,
  }) async {
    if (_connectionState == WsConnectionState.connecting ||
        _connectionState == WsConnectionState.connected) {
      return;
    }

    _setState(WsConnectionState.connecting);
    _lastError = null;

    final uri = Uri.parse('ws://$host:$port/api/chat/ws');
    Log.i('[HermesWS] Connecting to $uri');

    try {
      _ws = await WebSocket.connect(uri.toString()).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('连接超时'),
      );

      _ws!.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      _setState(WsConnectionState.connected);
      Log.i('[HermesWS] Connected');
    } catch (e) {
      _lastError = '连接失败: $e';
      _setState(WsConnectionState.error);
      Log.i('[HermesWS] $e');
      _scheduleReconnect();
    }
  }

  /// 断开连接
  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _ws?.close();
    _ws = null;
    _setState(WsConnectionState.disconnected);
  }

  // ── 消息发送 ──

  /// 初始化对话会话
  void sendStart({required List<Toy> toys}) {
    final toyApis = toys
        .where((t) => t.apiFunctions.isNotEmpty)
        .map((t) => {
              'id': t.id,
              'type': t.type.name,
              'name': t.name,
              'api': t.apiFunctions,
            })
        .toList();

    _sendJson({
      'action': 'start',
      'connected_toys': toyApis,
    });
  }

  /// 发送用户消息
  void sendMessage(String text) {
    if (_ws == null || _connectionState != WsConnectionState.connected) return;

    // 本地追加用户消息
    _messages.add(ChatMessage(role: 'user', content: text));
    notifyListeners();

    _sendJson({
      'action': 'message',
      'content': text,
    });
  }

  /// 关闭会话
  void sendClose() {
    _sendJson({'action': 'close'});
    disconnect();
  }

  // ── 内部 ──

  void _sendJson(Map<String, dynamic> data) {
    if (_ws == null) return;
    try {
      _ws!.add(jsonEncode(data));
    } catch (e) {
      Log.i('[HermesWS] Send error: $e');
      _lastError = '发送失败: $e';
      notifyListeners();
    }
  }

  void _onData(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = data['type'] as String? ?? '';

      switch (type) {
        case 'message':
          final content = data['content'] as String? ?? '';
          _messages.add(ChatMessage(
            role: 'assistant',
            content: content,
          ));
          notifyListeners();

        case 'playbook':
          final playScript = data['play_script'] as String? ??
              data['lua_script'] as String? ?? '';
          final rawName = data['playbook_name'] as String? ?? '未命名玩法';

          // 服务端返回"未命名玩法"时从脚本自动生成名称
          final playbookName = rawName == '未命名玩法'
              ? _autoNameFromLua(playScript)
              : rawName;
          final explanationRaw =
              data['explanation'] as Map<String, dynamic>?;

          PlaybookExplanation? explanation;
          if (explanationRaw != null) {
            final steps = (explanationRaw['steps'] as List? ?? [])
                .map((s) => PlaybookStep(
                      time: (s as Map)['time'] as String? ?? '',
                      action: s['action'] as String? ?? '',
                    ))
                .toList();
            explanation = PlaybookExplanation(
              name: playbookName,
              durationSeconds: explanationRaw['duration_seconds'] as int? ?? 0,
              steps: steps,
            );
          }

          _lastPlaybook = PlaybookResult(
            playbookName: playbookName,
            playScript: playScript,
            explanation: explanation ??
                PlaybookExplanation(
                    name: playbookName, durationSeconds: 0, steps: []),
          );

          // 也作为最后一条消息加入对话
          _messages.add(ChatMessage(
            role: 'assistant',
            content: '🔥 玩法方案已生成！点击下方按钮预览 👇',
            hasPreview: true,
          ));
          notifyListeners();

        case 'error':
          _lastError = data['content'] as String? ?? '未知错误';
          _messages.add(ChatMessage(
            role: 'assistant',
            content: '❌ $_lastError',
          ));
          notifyListeners();
      }
    } catch (e) {
      Log.i('[HermesWS] Parse error: $e');
    }
  }

  void _onError(dynamic error) {
    Log.i('[HermesWS] Error: $error');
    _lastError = '连接异常: $error';
    _setState(WsConnectionState.error);
    _scheduleReconnect();
  }

  void _onDone() {
    Log.i('[HermesWS] Closed');
    _ws = null;
    _setState(WsConnectionState.disconnected);
    _scheduleReconnect();
  }

  void _setState(WsConnectionState state) {
    if (_disposed) return;
    _connectionState = state;
    notifyListeners();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!_disposed) {
        Log.i('[HermesWS] Reconnecting...');
        connect();
      }
    });
  }

  /// 从 Lua 脚本自动生成玩法名称
  String _autoNameFromLua(String lua) {
    if (lua.isEmpty) return '自定义玩法';

    // 提取玩具 ID
    final toyIds = <String>{};
    final pattern = RegExp(r'(?:toy[._\[])?(\w+)(?:\])?:');
    for (final m in pattern.allMatches(lua)) {
      final id = m.group(1)!;
      if (id == 'wait' || id == 'print' || id == 'math') continue;
      toyIds.add(id);
    }
    if (toyIds.isEmpty) return '自定义玩法';

    bool has(String p) => toyIds.any((id) => id.toLowerCase().contains(p));

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

    return '${toyIds.length}机联动';
  }

  /// 清除对话历史
  void clearMessages() {
    _messages.clear();
    _lastPlaybook = null;
    _lastError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _ws?.close();
    super.dispose();
  }
}
