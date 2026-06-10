import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/chat_message.dart';
import '../models/playbook.dart';
import '../providers/toy_state.dart';
import '../providers/navigation_state.dart';
import '../providers/playbook_state.dart';
import '../providers/api_config.dart';
import '../services/hermes_api.dart';
import '../services/deepseek_api.dart';
import '../widgets/chat_bubble.dart';

/// 玩法设计对话页 — 双模式（Hermes / DeepSeek）
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _initialized = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _initSession();
    }
  }

  void _initSession() {
    final config = context.read<ApiConfig>();
    if (config.isHermes) {
      _initHermes();
    } else {
      _initDeepseek();
    }
  }

  // ── Hermes 模式 ──
  void _initHermes() {
    final api = context.read<HermesApiService>();
    final toys = context.read<ToyState>().connectedToys;
    if (api.messages.isNotEmpty) return;

    api.connect().then((_) {
      if (api.isConnected) {
        api.sendStart(toys: toys);
      }
    });
  }

  void _sendHermes(String text) {
    final api = context.read<HermesApiService>();
    if (!api.isConnected) {
      _showError('未连接到 Hermes 服务');
      return;
    }
    api.sendMessage(text);
    _inputController.clear();
    _scrollToBottom();
  }

  // ── DeepSeek 模式 ──
  void _initDeepseek() {
    final config = context.read<ApiConfig>();
    final api = context.read<DeepseekApiService>();
    final toys = context.read<ToyState>().connectedToys;
    if (api.messages.isNotEmpty) return;

    if (!config.hasDeepseekKey) {
      _showError('未配置 DeepSeek API Key');
      return;
    }

    api.configure(
      apiKey: config.deepseekApiKey,
      model: config.deepseekModel,
      baseUrl: config.deepseekBaseUrl,
    );

    api.start(toys);
  }

  void _sendDeepseek(String text) {
    final api = context.read<DeepseekApiService>();
    if (!api.isConfigured) {
      _showError('未配置 DeepSeek API Key');
      return;
    }
    api.sendMessage(text);
    _inputController.clear();
    _scrollToBottom();
  }

  // ── 通用 ──

  void _sendMessage(String text) {
    final config = context.read<ApiConfig>();
    if (config.isHermes) {
      _sendHermes(text);
    } else {
      _sendDeepseek(text);
    }
  }

  void _openPreview() {
    final config = context.read<ApiConfig>();
    PlaybookResult? result;

    if (config.isHermes) {
      final herm = context.read<HermesApiService>();
      result = herm.lastPlaybook;
    } else {
      final ds = context.read<DeepseekApiService>();
      result = ds.lastPlaybook;
    }

    if (result == null) return;

    final pbState = context.read<PlaybookState>();
    final playbook = Playbook(
      id: 'playbook_${DateTime.now().millisecondsSinceEpoch}',
      name: result.playbookName,
      luaScript: result.playScript,
      jsonPlay: result.playScript,
      explanation: result.explanation,
      createdAt: DateTime.now(),
      toyIds: [],
    );
    pbState.addPlaybook(playbook);
    context.read<NavigationState>().switchToTab(3);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppTheme.danger,
      ),
    );
  }

  /// 新建会话：重置对话、重新读取当前设备、重新初始化
  Future<void> _newSession() async {
    final config = context.read<ApiConfig>();

    // 弹确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('🔄 新建会话',
            style: TextStyle(color: AppTheme.primary)),
        content: const Text('当前对话将清空，重新获取已连接设备并开始新设计。',
            style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认新建',
                style: TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // 确保 context 还存活
    if (!mounted) return;

    // 重置服务状态
    if (config.isHermes) {
      final api = context.read<HermesApiService>();
      api.sendClose(); // 关闭 WS
      api.clearMessages(); // 清空对话历史
    } else {
      final api = context.read<DeepseekApiService>();
      api.clear(); // 清空对话
    }

    // 重置初始化标记，触发重新 init
    setState(() => _initialized = false);

    // 等待一帧让状态更新，然后重新初始化
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initSession();
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final config = context.watch<ApiConfig>();
    final toys = context.watch<ToyState>().connectedToys;

    // 根据模式选服务
    List<ChatMessage> messages;
    bool isConnected;
    bool isLoading;
    String statusText;
    Color statusColor;

    if (config.isHermes) {
      final api = context.watch<HermesApiService>();
      messages = api.messages;
      isConnected = api.isConnected;
      isLoading = false;
      statusText = isConnected ? 'Hermes' : '未连接';
      statusColor = isConnected ? AppTheme.success : AppTheme.danger;
    } else {
      final api = context.watch<DeepseekApiService>();
      messages = api.messages;
      isConnected = api.isConfigured;
      isLoading = api.isLoading;
      statusText = isConnected ? 'DeepSeek' : '未配置';
      statusColor = isConnected ? AppTheme.agent : AppTheme.danger;
    }

    return Scaffold(
      appBar: AppBar(
        leading: const Padding(
          padding: EdgeInsets.only(left: 12),
          child: Text('💬', style: TextStyle(fontSize: 20)),
        ),
        title: const Text('设计'),
        actions: [
          // 新会话
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 20),
            tooltip: '新建会话',
            onPressed: _newSession,
          ),
          // 模式切换
          PopupMenuButton<ApiMode>(
            icon: Icon(
              config.isHermes ? Icons.dns : Icons.cloud,
              color: config.isHermes ? AppTheme.primary : AppTheme.agent,
              size: 20,
            ),
            tooltip: '切换 API 模式',
            onSelected: (mode) {
              config.setMode(mode);
              _initialized = false;
              _initSession();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: ApiMode.hermes,
                child: Row(
                  children: [
                    Icon(Icons.dns, size: 18,
                        color: config.isHermes ? AppTheme.primary : null),
                    const SizedBox(width: 8),
                    const Text('Hermes 模式'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: ApiMode.deepseek,
                child: Row(
                  children: [
                    Icon(Icons.cloud, size: 18,
                        color: config.isDeepseek ? AppTheme.agent : null),
                    const SizedBox(width: 8),
                    const Text('DeepSeek 直连'),
                  ],
                ),
              ),
            ],
          ),
          // 状态指示
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  statusText,
                  style: TextStyle(fontSize: 11, color: statusColor),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 模式提示条
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: config.isHermes
                ? AppTheme.primary.withOpacity(0.1)
                : AppTheme.agent.withOpacity(0.1),
            child: Row(
              children: [
                Icon(
                  config.isHermes ? Icons.dns : Icons.cloud,
                  size: 13,
                  color: config.isHermes ? AppTheme.primary : AppTheme.agent,
                ),
                const SizedBox(width: 6),
                Text(
                  config.isHermes ? 'Hermes 模式' : 'DeepSeek 直连模式',
                  style: TextStyle(
                    fontSize: 11,
                    color:
                        config.isHermes ? AppTheme.primary : AppTheme.agent,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    config.setMode(
                        config.isHermes ? ApiMode.deepseek : ApiMode.hermes);
                    _initialized = false;
                    _initSession();
                  },
                  child: Text(
                    '切换',
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          config.isHermes ? AppTheme.primary : AppTheme.agent,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 玩具状态条
          if (toys.isNotEmpty)
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: AppTheme.bgSurface,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: toys
                      .map((t) => Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(t.type.icon,
                                    style:
                                        const TextStyle(fontSize: 14)),
                                const SizedBox(width: 4),
                                Text(t.name,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.success)),
                              ],
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),

          // 消息列表
          Expanded(child: _buildMessageList(messages, isLoading)),

          // 输入栏
          _buildInputBar(isConnected, toys, isLoading),
        ],
      ),
    );
  }

  Widget _buildMessageList(List<ChatMessage> messages, bool isLoading) {
    if (messages.isEmpty && isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppTheme.primary),
            ),
            SizedBox(height: 12),
            Text('正在生成...',
                style: TextStyle(color: AppTheme.textMuted)),
          ],
        ),
      );
    }

    if (messages.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 48, color: AppTheme.textMuted),
            SizedBox(height: 12),
            Text('输入玩法描述，开始对话设计',
                style: TextStyle(color: AppTheme.textMuted)),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index];
        return ChatBubble(
          message: msg,
          isLast: index == messages.length - 1,
          onPreview: msg.hasPreview ? _openPreview : null,
        );
      },
    );
  }

  Widget _buildInputBar(
      bool isConnected, List toys, bool isLoading) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        border: Border(
            top: BorderSide(color: AppTheme.bgSurface, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: !isConnected
                      ? '检查 API 配置...'
                      : toys.isEmpty
                          ? '先去连接玩具...'
                          : '输入玩法描述...',
                  hintStyle:
                      const TextStyle(color: AppTheme.textMuted),
                  filled: true,
                  fillColor: AppTheme.bgSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
                onSubmitted: (text) {
                  if (text.trim().isNotEmpty &&
                      isConnected &&
                      !isLoading) {
                    _sendMessage(text.trim());
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 18,
              backgroundColor: (isConnected && !isLoading)
                  ? AppTheme.primary
                  : AppTheme.textMuted,
              child: IconButton(
                icon: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded,
                        size: 18, color: Colors.white),
                onPressed: isLoading
                    ? null
                    : () {
                        final text =
                            _inputController.text.trim();
                        if (text.isNotEmpty && isConnected) {
                          _sendMessage(text);
                        }
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
