import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';

/// Tarjeta base: superficie sobria con borde fino.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.highlight,
    this.onLongPress,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Si se indica, borde y halo sutil de ese color (estado activo).
  final Color? highlight;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final h = highlight;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        border: Border.all(color: h?.withValues(alpha: 0.45) ?? AppColors.strokeSoft),
        boxShadow: h == null
            ? const []
            : [BoxShadow(color: h.withValues(alpha: 0.10), blurRadius: 28, spreadRadius: 1)],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          onLongPress: onLongPress,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Etiqueta de sección en mayúsculas espaciadas.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(text.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Punto de estado con pulso opcional.
class PulsingDot extends StatefulWidget {
  const PulsingDot({super.key, required this.color, this.pulse = false, this.size = 8});

  final Color color;
  final bool pulse;
  final double size;

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant PulsingDot old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_c.isAnimating) _c.repeat();
    if (!widget.pulse && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 2.6,
      height: s * 2.6,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = widget.pulse ? _c.value : 0.0;
          return Stack(
            alignment: Alignment.center,
            children: [
              if (widget.pulse)
                Container(
                  width: s + s * 1.6 * t,
                  height: s + s * 1.6 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: 0.35 * (1 - t)),
                  ),
                ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: s,
                height: s,
                decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Botón principal con escala al pulsar, estado de carga y háptica.
class PrimaryButton extends StatefulWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.color = AppColors.ember,
    this.foreground = Colors.white,
    this.outlined = false,
    this.height = 58,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final Color color;
  final Color foreground;
  final bool outlined;
  final double height;

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _down = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  @override
  Widget build(BuildContext context) {
    final bg = widget.outlined
        ? Colors.transparent
        : (_enabled ? widget.color : AppColors.surfaceHigher);
    final fg = widget.outlined
        ? (_enabled ? widget.color : AppColors.textTertiary)
        : (_enabled ? widget.foreground : AppColors.textTertiary);

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: _enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: _enabled ? (_) => setState(() => _down = false) : null,
        onTap: _enabled
            ? () {
                HapticFeedback.lightImpact();
                widget.onPressed!();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: const Duration(milliseconds: 120),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: widget.height,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppTheme.radiusM),
              border: widget.outlined
                  ? Border.all(color: fg.withValues(alpha: 0.5))
                  : null,
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: widget.loading
                  ? SizedBox(
                      key: const ValueKey('l'),
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
                    )
                  : FittedBox(
                      key: const ValueKey('c'),
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.icon != null) ...[
                            Icon(widget.icon, color: fg, size: 20),
                            const SizedBox(width: 10),
                          ],
                          Text(
                            widget.label.toUpperCase(),
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(color: fg),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Barras de señal RSSI.
class SignalBars extends StatelessWidget {
  const SignalBars({super.key, required this.bars, this.color = AppColors.textSecondary});

  final int bars;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        final on = i < bars;
        return Container(
          margin: const EdgeInsets.only(left: 2),
          width: 4,
          height: 5.0 + i * 3.5,
          decoration: BoxDecoration(
            color: on ? color : AppColors.stroke,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}
