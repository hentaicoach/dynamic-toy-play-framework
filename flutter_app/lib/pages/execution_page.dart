import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/playbook_state.dart';
import '../services/ble/toy_registry.dart';
import '../services/ble/drivers/toy_driver.dart';
import '../services/ble/drivers/fake_drivers.dart';
import '../services/executor/exports.dart';

/// 玩法执行页
class ExecutionPage extends StatefulWidget {
  final String? playbookId;
  final VoidCallback? onBack;
  final VoidCallback? onFinish;

  const ExecutionPage({
    super.key,
    this.playbookId,
    this.onBack,
    this.onFinish,
  });

  @override
  State<ExecutionPage> createState() => _ExecutionPageState();
}

class _ExecutionPageState extends State<ExecutionPage> {
  final ToyRegistry _registry = ToyRegistry(); // 单例，和蓝牙页共享
  JsonPlayExecutor? _executor;
  StreamSubscription? _logSub;
  ExecutionState _state = ExecutionState.idle;

  /// 当前日志显示偏移
  final ScrollController _logScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _registry.addListener(_onRegistryChanged);
    // 延迟初始化，等 widget 树挂载好再访问 inherited widgets
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initExecution();
    });
  }

  void _onRegistryChanged() {
    if (mounted) setState(() {});
  }

  void _initExecution() {
    final pb = context.read<PlaybookState>().getById(widget.playbookId ?? '');
    if (pb == null) {
      _postError('未找到玩法方案');
      return;
    }

    // 优先使用 JSON AST，没有则回退到 Lua
    String script;
    bool hasJson;
    if (pb.jsonPlay != null && pb.jsonPlay!.isNotEmpty) {
      script = pb.jsonPlay!;
      hasJson = true;
    } else if (pb.luaScript.trimLeft().startsWith('{')) {
      // 智能检测：luaScript 是 JSON 格式时也走 JSON 路径
      script = pb.luaScript;
      hasJson = true;
    } else {
      script = pb.luaScript;
      hasJson = false;
    }

    if (script.isEmpty) {
      _postError('玩法脚本为空');
      return;
    }

    setState(() => _state = ExecutionState.running);

    // 注册玩具驱动
    if (hasJson) {
      // JSON AST 模式：从 toy_ids 注册
      try {
        final data = jsonDecode(script) as Map<String, dynamic>;
        final toyIds = (data['toy_ids'] as List<dynamic>?)?.cast<String>() ?? [];
        for (final id in toyIds) {
          if (_registry[id] == null) {
            _registry.register(id, _guessDriver(id));
          }
        }
      } catch (_) {
        // 回退到 Lua 嗅探方式
        _registry.registerFakeFromLua(script);
      }
    } else {
      // Lua 回退模式
      _registry.registerFakeFromLua(script);
    }

    // 创建执行器
    _executor = JsonPlayExecutor(registry: _registry);
    _executor!.onPrint = (msg) {
      if (mounted) setState(() {});
      _scrollLog();
    };
    _executor!.onStateChange = (s) {
      if (mounted) setState(() => _state = s);
    };
    _executor!.onProgress = (cur, total) {
      if (mounted) setState(() {});
    };

    // 执行
    if (hasJson) {
      try {
        final data = jsonDecode(script) as Map<String, dynamic>;

        // 兼容 play 字段可能 `Map<String,dynamic>` 或 `String`（双编码）
        dynamic rawPlay = data['play'];
        if (rawPlay is String) {
          rawPlay = jsonDecode(rawPlay);
        }
        final playJson = (rawPlay as Map<String, dynamic>?) ?? data;

        final playBody = PlayBody.fromJson(playJson);
        _executor!.execute(playBody).then(_onExecutionDone);
      } catch (e) {
        if (mounted) {
          setState(() => _state = ExecutionState.error);
          _postError('JSON 解析失败: $e');
        }
      }
    } else {
      // Lua 已移除，不再支持
      if (mounted) {
        setState(() => _state = ExecutionState.error);
        _postError('不支持的脚本格式：仅支持 JSON AST');
      }
    }
  }

  void _onExecutionDone(ExecutionResult result) {
    if (mounted) {
      setState(() => _state = result.success
          ? ExecutionState.completed
          : ExecutionState.error);
      if (!result.success && result.error != '用户取消') {
        _showError(result.error ?? '执行失败');
      }
    }
  }

  /// 根据 toy ID 猜测驱动类型（与 ToyRegistry._guessDriver 一致）
  ToyDriver _guessDriver(String id) {
    final lower = id.toLowerCase();
    if (lower.contains('lock')) {
      return FakeLockDriver(toyId: id, toyName: id);
    }
    if (lower.contains('enema') || lower.contains('pump') || lower.contains('plug')) {
      return FakeEnemaDriver(toyId: id, toyName: id);
    }
    if (lower.contains('ems') || lower.contains('shock')) {
      return FakeEMSDriver(toyId: id, toyName: id);
    }
    return FakeVibratorDriver(toyId: id, toyName: id);
  }

  void _emergencyStop() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('🛑 紧急停止',
            style: TextStyle(color: AppTheme.danger)),
        content: const Text('所有玩具将立即关闭，确认停止？',
            style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              _executor?.cancel();
              _registry.stopAll();
              Navigator.pop(ctx);
              if (mounted) {
                setState(() => _state = ExecutionState.stopped);
              }
            },
            child: const Text('确认停止',
                style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
  }

  /// 延迟显示错误（可在 initState 中安全调用）
  void _postError(String msg) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showError(msg);
    });
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.danger),
    );
  }

  void _scrollLog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.animateTo(
          _logScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _registry.removeListener(_onRegistryChanged);
    _logSub?.cancel();
    _logScroll.dispose();
    _executor?.cancel();
    _registry.stopAll();
    _registry.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logLines = _registry.logs;
    final printOutput = _executor?.printOutput ?? [];

    final isRunning = _state == ExecutionState.running;
    final isFinished = _state == ExecutionState.completed;
    final isError = _state == ExecutionState.error;
    final isStopped = _state == ExecutionState.stopped;

    final statusIcon = isRunning
        ? '▶️'
        : isFinished
            ? '✅'
            : isError
                ? '❌'
                : isStopped
                    ? '🛑'
                    : '⏸️';
    final statusText = isRunning
        ? '执行中'
        : isFinished
            ? '执行完成'
            : isError
                ? '执行出错'
                : isStopped
                    ? '已停止'
                    : '空闲';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: isFinished ? (widget.onFinish ?? widget.onBack) : _emergencyStop,
        ),
        title: Text(statusText),
      ),
      body: Column(
        children: [
          // 状态大卡片
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isFinished
                    ? AppTheme.success.withOpacity(0.5)
                    : isError
                        ? AppTheme.danger.withOpacity(0.5)
                        : AppTheme.warning.withOpacity(0.5),
              ),
            ),
            child: Column(
              children: [
                Text(statusIcon, style: const TextStyle(fontSize: 36)),
                const SizedBox(height: 8),
                Text(statusText,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  '玩具: ${_registry.count} 个 · 日志: ${logLines.length} 条',
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 12),
                if (isRunning) ...[
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: AppTheme.primary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_executor?.currentLine ?? 0} / ${_executor?.totalLines ?? 0} 行',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textMuted),
                  ),
                ],
                if (isFinished)
                  Text(
                    '✅ 共 ${logLines.length} 条指令已执行',
                    style: const TextStyle(
                        fontSize: 14, color: AppTheme.success),
                  ),
              ],
            ),
          ),

          // 注册的玩具列表
          if (_registry.count > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: _registry.drivers.entries.map((e) {
                    return Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.bgSurface,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${e.key} (${e.value.toyName})',
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.success),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

          const SizedBox(height: 8),

          // print 输出
          if (printOutput.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('📢 执行输出',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.agent,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  ...printOutput.map((line) => Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(line,
                            style: const TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                color: AppTheme.textSecondary)),
                      )),
                ],
              ),
            ),

          const SizedBox(height: 8),

          // 详细日志
          SizedBox(
            height: 240, // 固定高度可滚动窗口
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.bgSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('📋 指令日志 (${logLines.length})',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.bold)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => _registry.clearLogs(),
                        child: const Text('清空',
                            style: TextStyle(
                                fontSize: 11, color: AppTheme.textMuted)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: logLines.isEmpty
                        ? const Center(
                            child: Text('等待指令...',
                                style: TextStyle(
                                    color: AppTheme.textMuted, fontSize: 12)),
                          )
                        : ListView.builder(
                            controller: _logScroll,
                            itemCount: logLines.length,
                            itemBuilder: (_, i) {
                              final entry = logLines[i];
                              final color = entry.level == 'ERROR'
                                  ? AppTheme.danger
                                  : entry.level == 'ACTION'
                                      ? AppTheme.primary
                                      : AppTheme.textSecondary;
                              return Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 1),
                                child: Text(
                                  entry.formatted,
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontFamily: 'monospace',
                                    color: color,
                                    height: 1.3,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),

          // 底部按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: isRunning
                    ? ElevatedButton.icon(
                        onPressed: _emergencyStop,
                        icon: const Icon(Icons.stop_circle_outlined,
                            size: 24),
                        label: const Text('🛑  紧急停止',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.danger,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      )
                    : ElevatedButton.icon(
                        onPressed: widget.onFinish ?? widget.onBack,
                        icon: const Icon(Icons.check_circle_outline,
                            size: 24),
                        label: Text(
                          isFinished ? '✅  完成' : '🔙  返回',
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isFinished
                              ? AppTheme.success
                              : AppTheme.textMuted,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
