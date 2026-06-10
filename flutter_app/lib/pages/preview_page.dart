import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/playbook_state.dart';
import '../widgets/step_timeline.dart';

/// 方案预览页（玩法管理 tab 的子页）
class PreviewPage extends StatelessWidget {
  final String? playbookId;
  final VoidCallback? onBack;
  final void Function(String? playbookId)? onExecute;

  const PreviewPage({
    super.key,
    this.playbookId,
    this.onBack,
    this.onExecute,
  });

  @override
  Widget build(BuildContext context) {
    final playbookState = context.watch<PlaybookState>();
    final pb = playbookState.getById(playbookId ?? '');

    if (pb == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: onBack ?? () => Navigator.pop(context),
          ),
          title: const Text('方案预览'),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off, size: 48, color: AppTheme.textMuted),
              SizedBox(height: 12),
              Text('未找到该玩法方案',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 16)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack ?? () => Navigator.pop(context),
        ),
        title: const Text('方案预览'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 方案名称
            Text(pb.name, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.timer_outlined,
                    size: 16, color: AppTheme.textMuted),
                const SizedBox(width: 4),
                Text(
                  '⏱ 总时长：约 ${pb.durationDisplay}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '玩法 ID: ${pb.id}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.textMuted,
                  ),
            ),

            const SizedBox(height: 20),

            // 使用到的玩具
            if (pb.toyIds.isNotEmpty) ...[
              Text('玩具', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: pb.toyIds.map((id) {
                  final emoji = _toyEmoji(id);
                  return Chip(
                    avatar: Text(emoji, style: const TextStyle(fontSize: 16)),
                    label: Text(id, style: const TextStyle(fontSize: 12)),
                    backgroundColor: AppTheme.bgCard,
                    side: BorderSide.none,
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],

            // 步骤时间轴
            Text('执行步骤', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            StepTimeline(steps: pb.explanation.steps),

            const SizedBox(height: 20),

            // JSON AST（可折叠）
            Text('玩法脚本', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ExpansionTile(
              title: const Text('点击展开查看脚本源码',
                  style: TextStyle(fontSize: 13, color: AppTheme.agent)),
              backgroundColor: AppTheme.bgSurface,
              collapsedBackgroundColor: AppTheme.bgSurface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              collapsedShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    pb.jsonPlay ?? pb.luaScript,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: AppTheme.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 操作按钮
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () => onExecute?.call(pb.id),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('▶  执行',
                          style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.success,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('返回',
                          style: TextStyle(fontSize: 14)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textMuted,
                        side: const BorderSide(color: AppTheme.textMuted),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  String _toyEmoji(String id) {
    if (id.contains('lock')) return '🔒';
    if (id.contains('enema')) return '💧';
    if (id.contains('ems')) return '⚡';
    if (id.contains('mast') || id.contains('vibe')) return '🌀';
    return '❓';
  }
}
