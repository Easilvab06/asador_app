import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'controllers/bluetooth_controller.dart';
import 'controllers/motor_controller.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'screens/splash/splash_screen.dart';

class AsadorApp extends ConsumerStatefulWidget {
  const AsadorApp({super.key});

  @override
  ConsumerState<AsadorApp> createState() => _AsadorAppState();
}

class _AsadorAppState extends ConsumerState<AsadorApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      // (2) Al volver a la app se revalida Bluetooth (pudo apagarse fuera).
      onResume: () => unawaited(ref.read(bluetoothControllerProvider.notifier).refreshAdapter()),
      // (5) Cierre de la app: parada opcional "best effort" (ver Ajustes).
      onDetach: () => unawaited(ref.read(motorControllerProvider.notifier).onAppDetached()),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const SplashScreen(),
    );
  }
}
