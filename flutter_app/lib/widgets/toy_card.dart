import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/toy.dart';

class ToyCard extends StatelessWidget {
  final Toy toy;
  const ToyCard({super.key, required this.toy});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: toy.isConnected ? AppTheme.success.withOpacity(0.3) : AppTheme.textMuted.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Text(toy.type.icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(toy.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                Text(
                  toy.apiFunctions.entries.map((e) => '${e.key}').join('  ·  '),
                  style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: toy.isConnected ? AppTheme.success.withOpacity(0.15) : AppTheme.textMuted.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              toy.isConnected ? '● 已连接' : '○ 离线',
              style: TextStyle(
                fontSize: 11,
                color: toy.isConnected ? AppTheme.success : AppTheme.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
