// lib/main.dart

import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';

void main() {
  runApp(const EvChargeApp());
}

class EvChargeApp extends StatelessWidget {
  const EvChargeApp({super.key});


  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EV Charge Finder',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(),
    );
  }
}