import 'package:flutter/material.dart';

import 'theme/app_colors.dart';
import 'screens/login/login_screen.dart';

void main() {
  runApp(const EwayLinkApp());
}

class EwayLinkApp extends StatelessWidget {
  const EwayLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EWAY LINK',
      debugShowCheckedModeBanner: false,

      theme: ThemeData(
        useMaterial3: true,

        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
        ),

        scaffoldBackgroundColor: AppColors.background,

        fontFamily: 'Segoe UI',
      ),

      home: const LoginScreen(),
    );
  }
}