import 'package:flutter/material.dart';

class AppColors {
  // Splash Screen Gradient
  static const LinearGradient splashGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color(0xFF78C0FE), // blue
      Color(0xFF78C0FE), // blue
      Color(0xFF0677D8), // deep blue
    ],

    stops: [0.0,0.0, 1.0],
  );

  // Common Colors
  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF000000);
  static const blue = Color(0xFF78C0FE);
}