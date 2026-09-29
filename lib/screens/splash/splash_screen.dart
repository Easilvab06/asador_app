import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/bluetooth_controller.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../home/home_screen.dart';

/// Splash breve (el original esperaba 4 s fijos; aquí ~1,3 s mientras se
/// inicializa el estado Bluetooth).
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();

  @override
  void initState() {
    super.initState();
    // Instancia temprana del controlador: empieza a leer el adaptador.
    ref.read(bluetoothControllerProvider);
    Future<void>.delayed(const Duration(milliseconds: 1300), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, a, __) => FadeTransition(opacity: a, child: const HomeScreen()),
      ));
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = Curves.easeOutCubic.transform(_c.value);
            return Opacity(
              opacity: t,
              child: Transform.scale(
                scale: 0.94 + 0.06 * t,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _Logo(size: 76),
                    const SizedBox(height: 24),
                    Text(
                      AppConstants.appName,
                      style: theme.textTheme.headlineMedium?.copyWith(letterSpacing: 10 * t),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppConstants.appTagline,
                      style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Marca: disco con llama estilizada.
class _Logo extends StatelessWidget {
  const _Logo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.emberSoft,
        border: Border.all(color: AppColors.ember.withValues(alpha: 0.5), width: 1.5),
        boxShadow: const [BoxShadow(color: AppColors.emberGlow, blurRadius: 40)],
      ),
      child: Icon(Icons.local_fire_department_rounded, color: AppColors.ember, size: size * 0.5),
    );
  }
}

/// Logo reutilizable en otras pantallas.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) => _Logo(size: size);
}
