import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/playbook.dart';

class StepTimeline extends StatelessWidget {
  final List<PlaybookStep> steps;
  const StepTimeline({super.key, required this.steps});

  Color _getColor(int index) {
    final time = steps[index].time;
    if (time.contains('⛰️') || time.contains('climax') || steps[index].action.contains('⛰️')) {
      return AppTheme.stageClimax;
    }
    if (time == '开始' || steps[index].action.contains('停止') || steps[index].action.contains('解锁')) {
      return AppTheme.stageEnd;
    }
    if (time == '等待') return AppTheme.stageWait;
    if (steps[index].action.contains('递增') || steps[index].action.contains('加强')) {
      return AppTheme.stageBuild;
    }
    return AppTheme.stageStart;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(steps.length, (i) {
        final step = steps[i];
        final color = _getColor(i);
        final isLast = i == steps.length - 1;

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 时间轴
              SizedBox(
                width: 70,
                child: Column(
                  children: [
                    Container(
                      width: 68,
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        step.time,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: color == AppTheme.stageStart || color == AppTheme.stageEnd
                              ? AppTheme.success
                              : color == AppTheme.stageClimax
                                  ? AppTheme.danger
                                  : AppTheme.warning,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),

              // 竖线 + 圆点
              SizedBox(
                width: 24,
                child: Column(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(color: color.withOpacity(0.5), width: 2),
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: color.withOpacity(0.3),
                        ),
                      ),
                  ],
                ),
              ),

              // 步骤内容
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withOpacity(0.2)),
                  ),
                  child: Text(
                    step.action,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
