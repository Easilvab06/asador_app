import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_colors.dart';
import 'common.dart';

/// Selector de velocidad por niveles discretos (el protocolo original solo
/// admite enteros 4..8). Barras ascendentes + arrastre/tap + háptica.
class SpeedControl extends StatelessWidget {
  const SpeedControl({
    super.key,
    required this.level,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.running,
    this.enabled = true,
  });

  final int level;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final bool running;
  final bool enabled;

  int get _count => max - min + 1;
  int get _index => (level - min).clamp(0, _count - 1);
  int get percent => (((_index + 1) / _count) * 100).round();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = enabled ? AppColors.ember : AppColors.textTertiary;

    return AppCard(
      highlight: running && enabled ? AppColors.ember : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(
            'Velocidad',
            trailing: Text(
              'Nivel ${_index + 1}/$_count',
              style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(end: percent.toDouble()),
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => Text(
                  v.round().toString(),
                  style: theme.textTheme.displayLarge?.copyWith(
                    fontSize: 56,
                    height: 1,
                    color: enabled ? AppColors.textPrimary : AppColors.textTertiary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 4),
                child: Text('%',
                    style: theme.textTheme.titleLarge?.copyWith(color: AppColors.textSecondary)),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  running ? 'Velocidad del motor' : 'Preselección',
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _LevelBars(
            count: _count,
            index: _index,
            color: color,
            enabled: enabled,
            onIndex: (i) {
              final next = min + i;
              if (next != level) {
                HapticFeedback.selectionClick();
                onChanged(next);
              }
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('Lento', style: theme.textTheme.labelSmall),
              const Spacer(),
              Text('Rápido', style: theme.textTheme.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _LevelBars extends StatelessWidget {
  const _LevelBars({
    required this.count,
    required this.index,
    required this.color,
    required this.enabled,
    required this.onIndex,
  });

  final int count;
  final int index;
  final Color color;
  final bool enabled;
  final ValueChanged<int> onIndex;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      void pick(double dx) {
        final i = (dx / box.maxWidth * count).floor().clamp(0, count - 1);
        onIndex(i);
      }

      return Semantics(
        slider: true,
        value: 'Nivel ${index + 1} de $count',
        increasedValue: index + 1 < count ? 'Nivel ${index + 2}' : null,
        decreasedValue: index > 0 ? 'Nivel $index' : null,
        onIncrease: enabled && index + 1 < count ? () => onIndex(index + 1) : null,
        onDecrease: enabled && index > 0 ? () => onIndex(index - 1) : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (d) => pick(d.localPosition.dx) : null,
          onHorizontalDragUpdate: enabled ? (d) => pick(d.localPosition.dx) : null,
          child: SizedBox(
            height: 64,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(count, (i) {
                final on = i <= index;
                final h = 22.0 + (42.0 * (i + 1) / count);
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i == count - 1 ? 0 : 8),
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: 220 + i * 30),
                      curve: Curves.easeOutCubic,
                      height: h,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: on ? color.withValues(alpha: 0.35 + 0.65 * (i + 1) / count) : AppColors.surfaceHigher,
                        border: Border.all(
                          color: i == index && enabled ? color : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      );
    });
  }
}
