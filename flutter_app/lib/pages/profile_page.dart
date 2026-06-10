import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/toy_state.dart';
import '../providers/api_config.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  static const List<String> _avatars = [
    '🐱', '🐶', '🐰', '🦊', '🐼', '🐸', '🐙', '🦄',
  ];

  @override
  Widget build(BuildContext context) {
    final toyCount = context.watch<ToyState>().count;

    return Scaffold(
      appBar: AppBar(
        title: const Text('个人'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _showSettings(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 12),
            // 头像
            GestureDetector(
              onTap: () => _showAvatarPicker(context),
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(color: AppTheme.primary, width: 2),
                ),
                child: const Center(
                  child: Text('🐙', style: TextStyle(fontSize: 36)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text('YOKONEX 玩家',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('v1.0.0',
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            const SizedBox(height: 24),

            // 概览卡片
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statItem(Icons.bluetooth_connected, '$toyCount', '已连接'),
                  _statItem(Icons.folder, '4', '玩法'),
                  _statItem(Icons.timer_outlined, '0', '总时长'),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 连接历史
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('连接历史',
                    style: Theme.of(context).textTheme.titleMedium),
                TextButton(
                  onPressed: () {},
                  child: const Text('清除'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _historyCard('灌肠器（充气肛塞）', '2026-06-10 15:32'),
            _historyCard('飞机杯 + 电击器', '2026-06-09 22:15'),
            _historyCard('电子锁 + 全套', '2026-06-08 20:00'),

            const SizedBox(height: 24),

            // 偏好设置
            Row(
              children: [
                Text('偏好设置',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            _settingTile(Icons.dark_mode, '深色模式', true, (v) {}),
            _settingTile(Icons.vibration, '振动反馈', true, (v) {}),
            _settingTile(Icons.notifications_none, '通知', false, (v) {}),

            // Debug 模式 —— 仅 UI + FakeDriver
            Consumer<ApiConfig>(
              builder: (_, config, __) => Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: SwitchListTile(
                  dense: true,
                  secondary: const Icon(Icons.bug_report,
                      color: AppTheme.warning, size: 20),
                  title: const Text('Debug 模式',
                      style: TextStyle(fontSize: 14)),
                  subtitle: Text(
                    config.debugMode ? 'FakeDriver + UI 模拟' : '使用真实 BLE（未实现）',
                    style: TextStyle(
                        fontSize: 10,
                        color: config.debugMode
                            ? AppTheme.warning
                            : AppTheme.textMuted),
                  ),
                  value: config.debugMode,
                  activeColor: AppTheme.warning,
                  onChanged: (v) => config.setDebugMode(v),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // API 设置
            Row(
              children: [
                Text('API 设置',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            _buildApiSettings(context),

            const SizedBox(height: 32),

            // 关于
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showAbout(context),
                icon: const Icon(Icons.info_outline, size: 18),
                label: const Text('关于 YOKONEX Play'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textMuted,
                  side: const BorderSide(color: AppTheme.textMuted),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _statItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: AppTheme.primary, size: 24),
        const SizedBox(height: 6),
        Text(value,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary)),
        Text(label,
            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
      ],
    );
  }

  Widget _historyCard(String name, String time) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.history, color: AppTheme.textMuted, size: 20),
        title: Text(name, style: const TextStyle(fontSize: 13)),
        trailing: Text(time,
            style: const TextStyle(
                fontSize: 11, color: AppTheme.textMuted)),
      ),
    );
  }

  Widget _settingTile(IconData icon, String title, bool value, ValueChanged<bool> onChanged) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: SwitchListTile(
        dense: true,
        secondary: Icon(icon, color: AppTheme.textMuted, size: 20),
        title: Text(title, style: const TextStyle(fontSize: 14)),
        value: value,
        activeColor: AppTheme.primary,
        onChanged: onChanged,
      ),
    );
  }

  void _showAvatarPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('选择头像', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _avatars.map((a) => GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.bgSurface,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Center(child: Text(a, style: const TextStyle(fontSize: 24))),
                ),
              )).toList(),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildApiSettings(BuildContext context) {
    final config = context.watch<ApiConfig>();
    return Column(
      children: [
        // 模式选择
        Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: RadioListTile<ApiMode>(
            dense: true,
            secondary: const Icon(Icons.dns, color: AppTheme.primary, size: 20),
            title: const Text('Hermes 模式（需要本地服务）',
                style: TextStyle(fontSize: 13)),
            value: ApiMode.hermes,
            groupValue: config.mode,
            activeColor: AppTheme.primary,
            onChanged: (v) => config.setMode(v!),
          ),
        ),
        Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: RadioListTile<ApiMode>(
            dense: true,
            secondary:
                const Icon(Icons.cloud, color: AppTheme.agent, size: 20),
            title: const Text('DeepSeek 直连（无需服务）',
                style: TextStyle(fontSize: 13)),
            subtitle: Text(
              config.hasDeepseekKey ? '✓ 已配置' : '✗ 未配置',
              style: TextStyle(
                fontSize: 11,
                color:
                    config.hasDeepseekKey ? AppTheme.success : AppTheme.danger,
              ),
            ),
            value: ApiMode.deepseek,
            groupValue: config.mode,
            activeColor: AppTheme.agent,
            onChanged: (v) => config.setMode(v!),
          ),
        ),
        // DeepSeek Key 配置
        Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.vpn_key, color: AppTheme.textMuted, size: 20),
            title: const Text('DeepSeek API Key', style: TextStyle(fontSize: 13)),
            subtitle: Text(
              config.hasDeepseekKey
                  ? '已设置 (${config.deepseekApiKey.substring(0, 8)}...)'
                  : '未设置',
              style: TextStyle(
                fontSize: 11,
                color: config.hasDeepseekKey
                    ? AppTheme.success
                    : AppTheme.danger,
              ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit, size: 18, color: AppTheme.textMuted),
              onPressed: () => _showApiKeyInput(context, config),
            ),
          ),
        ),
        // DeepSeek 模型
        Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            dense: true,
            leading:
                const Icon(Icons.smart_toy, color: AppTheme.textMuted, size: 20),
            title: Text(config.deepseekModel, style: const TextStyle(fontSize: 13)),
            trailing: IconButton(
              icon: const Icon(Icons.edit, size: 18, color: AppTheme.textMuted),
              onPressed: () => _showModelInput(context, config),
            ),
          ),
        ),
      ],
    );
  }

  void _showApiKeyInput(BuildContext context, ApiConfig config) {
    final controller = TextEditingController(text: config.deepseekApiKey);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('DeepSeek API Key',
            style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: 'sk-...',
            hintStyle: TextStyle(color: AppTheme.textMuted),
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                config.setDeepseekKey(controller.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showModelInput(BuildContext context, ApiConfig config) {
    final controller = TextEditingController(text: config.deepseekModel);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('DeepSeek 模型',
            style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: 'deepseek-v4-flash',
            hintStyle: TextStyle(color: AppTheme.textMuted),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                config.setDeepseekModel(controller.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'YOKONEX Play',
      applicationVersion: 'v1.0.0',
      applicationIcon: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(child: Text('🎮', style: TextStyle(fontSize: 24))),
      ),
      children: [
        const Text('YOKONEX Play 是役次元（YOKONEX）生态的动态玩具玩法框架。\n\n通过 AI 对话设计玩法，自动生成格式化玩法脚本，在 APP 上预览、执行和分享。'),
      ],
    );
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const ListTile(
              leading: Icon(Icons.language, color: AppTheme.textMuted),
              title: Text('语言', style: TextStyle(fontSize: 14)),
              trailing: Text('简体中文', style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
            ),
            const ListTile(
              leading: Icon(Icons.privacy_tip_outlined, color: AppTheme.textMuted),
              title: Text('隐私模式', style: TextStyle(fontSize: 14)),
              trailing: Text('关闭', style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
