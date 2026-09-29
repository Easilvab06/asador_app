import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/bluetooth_controller.dart';
import '../../controllers/motor_controller.dart';
import '../../controllers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../models/bluetooth_models.dart';
import '../../models/motor_state.dart';
import '../../widgets/common.dart';
import '../../widgets/connection_status.dart';
import '../../widgets/direction_button.dart';
import '../../widgets/rotisserie_animation.dart';
import '../../widgets/speed_control.dart';
import '../../widgets/stop_button.dart';
import '../settings/settings_screen.dart';

class MotorControlScreen extends ConsumerWidget {
  const MotorControlScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bt = ref.watch(bluetoothControllerProvider);
    final motor = ref.watch(motorControllerProvider);
    final cfg = ref.watch(protocolConfigProvider);
    final motorCtrl = ref.read(motorControllerProvider.notifier);
    final linked = bt.isConnected;

    // Feedback de errores y de pérdida de enlace.
    ref.listen<String?>(motorControllerProvider.select((m) => m.lastError), (_, err) {
      if (err == null) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(err)));
      motorCtrl.clearError();
    });
    ref.listen<LinkStatus>(bluetoothControllerProvider.select((s) => s.link), (prev, next) {
      if (prev == LinkStatus.connected && next != LinkStatus.connected) {
        HapticFeedback.vibrate();
      }
      if (prev == LinkStatus.reconnecting && next == LinkStatus.connected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reconectado. Verifica el estado del motor.')),
        );
      }
    });

    final speed01 = cfg.levels <= 1 ? 1.0 : (motor.level - cfg.speedMin) / (cfg.levels - 1);

    final hero = _MotorHero(
      motor: motor,
      linked: linked,
      speed01: speed01,
      onStart: () => unawaited(motorCtrl.start()),
    );
    final speed = SpeedControl(
      level: motor.level,
      min: cfg.speedMin,
      max: cfg.speedMax,
      running: motor.isRunning,
      enabled: linked && !motor.isReversing,
      onChanged: motorCtrl.setLevel,
    );
    final direction = DirectionControl(
      direction: motor.direction,
      phase: motor.reversePhase,
      progress: motor.reverseProgress,
      enabled: linked,
      onReverse: () => unawaited(motorCtrl.reverse()),
      onSyncLabel: () => unawaited(_confirmSyncLabel(context, ref)),
    );

    return PopScope(
      canPop: true,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _TopBar(
                deviceName: bt.device?.displayName ?? 'Asador',
                link: bt.link,
                attempt: bt.reconnectAttempt,
                onDisconnect: () => unawaited(_confirmDisconnect(context, ref)),
              ),
              Expanded(
                child: LayoutBuilder(builder: (context, box) {
                  final wide = box.maxWidth >= 760;
                  final pad = box.maxWidth < 380 ? 16.0 : 20.0;
                  final linkBanner = _LinkBanner(
                    link: bt.link,
                    attempt: bt.reconnectAttempt,
                    onReconnect: bt.device == null
                        ? null
                        : () => unawaited(
                            ref.read(bluetoothControllerProvider.notifier).connect(bt.device!)),
                  );

                  if (wide) {
                    return SingleChildScrollView(
                      padding: EdgeInsets.all(pad),
                      child: Column(
                        children: [
                          linkBanner,
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 5, child: hero),
                              SizedBox(width: pad),
                              Expanded(
                                flex: 6,
                                child: Column(children: [speed, SizedBox(height: pad), direction]),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(pad, 8, pad, pad),
                        children: [
                          linkBanner,
                          hero,
                          SizedBox(height: pad * 0.8),
                          speed,
                          SizedBox(height: pad * 0.8),
                          direction,
                        ],
                      ),
                    ),
                  );
                }),
              ),
              // STOP fijo: siempre visible, sin scroll.
              _StopDock(
                enabled: linked,
                emphasized: motor.run != MotorRun.stopped || motor.isReversing,
                onStop: () => unawaited(motorCtrl.stop()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDisconnect(BuildContext context, WidgetRef ref) async {
    final motor = ref.read(motorControllerProvider);
    final bt = ref.read(bluetoothControllerProvider.notifier);
    final nav = Navigator.of(context);

    if (motor.run == MotorRun.stopped || !ref.read(bluetoothControllerProvider).isConnected) {
      await bt.disconnect();
      if (nav.canPop()) nav.pop();
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        title: const Text('¿Desconectar el asador?'),
        content: const Text(
          'El motor puede estar girando. Al desconectar, lo que ocurra depende '
          'del firmware del ESP32 (puede seguir girando).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'keep'),
            child: const Text('Solo desconectar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, 'stop'),
            child: const Text('Detener y desconectar'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    if (choice == 'stop') await ref.read(motorControllerProvider.notifier).stop();
    await bt.disconnect();
    if (nav.canPop()) nav.pop();
  }

  Future<void> _confirmSyncLabel(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        title: const Text('Corregir etiqueta de sentido'),
        content: const Text(
          'El ESP32 no informa el sentido real. Si el asador gira al revés de lo '
          'que muestra la app, corrige la etiqueta. No se envía ningún comando.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Corregir')),
        ],
      ),
    );
    if (ok == true) await ref.read(motorControllerProvider.notifier).syncDirectionLabel();
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.deviceName,
    required this.link,
    required this.attempt,
    required this.onDisconnect,
  });

  final String deviceName;
  final LinkStatus link;
  final int attempt;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Atrás',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(deviceName, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                ConnectionPill(link: link, attempt: attempt),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz_rounded),
            color: AppColors.surfaceHigh,
            onSelected: (v) {
              if (v == 'settings') {
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
              } else if (v == 'disconnect') {
                onDisconnect();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'settings', child: Text('Ajustes y protocolo')),
              PopupMenuItem(value: 'disconnect', child: Text('Desconectar')),
            ],
          ),
        ],
      ),
    );
  }
}

class _MotorHero extends StatelessWidget {
  const _MotorHero({
    required this.motor,
    required this.linked,
    required this.speed01,
    required this.onStart,
  });

  final MotorState motor;
  final bool linked;
  final double speed01;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = motor.isRunning;
    final stateColor = switch (motor.run) {
      MotorRun.running => AppColors.ember,
      MotorRun.stopped => AppColors.textSecondary,
      MotorRun.unknown => AppColors.warning,
    };
    final stateText = motor.run == MotorRun.unknown ? 'Sin confirmar' : motor.run.label;

    return AppCard(
      highlight: running && linked ? AppColors.ember : null,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(
            'Motor',
            trailing: AnimatedOpacity(
              opacity: motor.sending ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.textTertiary),
              ),
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, box) {
            final size = (box.maxWidth * 0.62).clamp(150.0, 280.0);
            return Center(
              child: SizedBox.square(
                dimension: size,
                child: RotisserieAnimation(
                  running: running,
                  speed01: speed01,
                  clockwise: motor.direction == MotorDirection.clockwise,
                  enabled: linked,
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text(
                linked ? stateText : 'Sin conexión',
                key: ValueKey('$stateText$linked'),
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: linked ? (running ? AppColors.textPrimary : stateColor) : AppColors.textTertiary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              motor.run == MotorRun.unknown && linked
                  ? 'El ESP32 no informa su estado. Pulsa Iniciar o Detener.'
                  : '${motor.direction == MotorDirection.clockwise ? '↻' : '↺'} ${motor.direction.label}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 18),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: running ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: PrimaryButton(
              label: 'Iniciar giro',
              icon: Icons.play_arrow_rounded,
              onPressed: linked && !motor.isReversing ? onStart : null,
            ),
            secondChild: Container(
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.emberSoft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const PulsingDot(color: AppColors.ember, pulse: true, size: 7),
                  Text(
                    'GIRANDO',
                    style: theme.textTheme.labelLarge?.copyWith(color: AppColors.ember),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkBanner extends StatelessWidget {
  const _LinkBanner({required this.link, required this.attempt, required this.onReconnect});

  final LinkStatus link;
  final int attempt;
  final VoidCallback? onReconnect;

  @override
  Widget build(BuildContext context) {
    final show = link != LinkStatus.connected;
    final theme = Theme.of(context);
    final reconnecting = link == LinkStatus.reconnecting || link == LinkStatus.connecting;
    final color = reconnecting ? AppColors.warning : AppColors.danger;

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      child: !show
          ? const SizedBox(width: double.infinity)
          : Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  if (reconnecting)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: color),
                    )
                  else
                    Icon(Icons.link_off_rounded, color: color, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      reconnecting
                          ? 'Conexión perdida. Reconectando (intento $attempt)… Controles bloqueados.'
                          : 'Asador desconectado. Los controles están bloqueados.',
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textPrimary),
                    ),
                  ),
                  if (!reconnecting && onReconnect != null)
                    TextButton(
                      onPressed: onReconnect,
                      child: Text('Reconectar', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ),
    );
  }
}

class _StopDock extends StatelessWidget {
  const _StopDock({required this.enabled, required this.emphasized, required this.onStop});

  final bool enabled;
  final bool emphasized;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewPadding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + bottom),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.strokeSoft)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: StopButton(onPressed: onStop, enabled: enabled, emphasized: emphasized),
        ),
      ),
    );
  }
}
