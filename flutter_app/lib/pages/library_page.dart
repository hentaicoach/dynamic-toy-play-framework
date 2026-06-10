import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/playbook_state.dart';
import '../services/playbook_import.dart';

/// 玩法库（玩法管理 tab 的根页）
class LibraryPage extends StatelessWidget {
  final void Function(String? playbookId)? onPreview;

  const LibraryPage({super.key, this.onPreview});

  @override
  Widget build(BuildContext context) {
    final playbookState = context.watch<PlaybookState>();
    final playbooks = playbookState.playbooks;

    return Scaffold(
      appBar: AppBar(
        title: const Text('🎮 玩法'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: '从服务端导入',
            onPressed: () => _importFromServer(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: '清空所有',
            onPressed: playbooks.isEmpty
                ? null
                : () => _confirmClear(context, playbookState),
          ),
        ],
      ),
      body: playbooks.isEmpty
          ? _buildEmptyState(context)
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: playbooks.length,
              itemBuilder: (context, index) {
                final pb = playbooks[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onPreview?.call(pb.id),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppTheme.bgSurface,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                              child: Icon(Icons.play_circle_outline,
                                  color: AppTheme.primary, size: 24),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(pb.name,
                                    style: const TextStyle(fontSize: 15)),
                                const SizedBox(height: 4),
                                Text(
                                  '${pb.createdAt.toString().substring(0, 10)}  ·  ${pb.durationDisplay}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textMuted),
                                ),
                                if (pb.toyIds.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      pb.toyIds.join(' · '),
                                      style: const TextStyle(
                                          fontSize: 10,
                                          color: AppTheme.textMuted),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.play_arrow_rounded,
                                color: AppTheme.success),
                            onPressed: () => onPreview?.call(pb.id),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: AppTheme.textMuted, size: 20),
                            onPressed: () =>
                                playbookState.removePlaybook(pb.id),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open,
              size: 48, color: AppTheme.textMuted.withOpacity(0.6)),
          const SizedBox(height: 12),
          const Text('还没有缓存玩法',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 16)),
          const SizedBox(height: 4),
          const Text('先去设计一套或从服务端导入吧！',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => _importFromServer(context),
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text('从服务端导入'),
          ),
        ],
      ),
    );
  }

  void _importFromServer(BuildContext context) async {
    final state = context.read<PlaybookState>();
    final importService = PlaybookImportService();

    // 显示导入中
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('正在从服务端导入...'),
          ],
        ),
        duration: Duration(seconds: 30),
      ),
    );

    try {
      final playbooks = await importService.fetchFromServer();
      await state.importAll(playbooks);

      // 关闭旧 SnackBar，显示成功
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ 成功导入 ${playbooks.length} 个玩法方案'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 导入失败: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  void _confirmClear(BuildContext context, PlaybookState state) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('清空所有玩法',
            style: TextStyle(color: AppTheme.danger)),
        content: const Text('确认清空所有本地缓存的玩法方案？',
            style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              state.clear();
              Navigator.pop(ctx);
            },
            child: const Text('确认清空',
                style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
  }
}
