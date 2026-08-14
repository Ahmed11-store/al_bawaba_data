import 'package:flutter/material.dart';

/// Central color + text theme for البوابة, matching the design spec:
/// deep dark-blue/charcoal background, navy accent cards, emerald
/// green for clear plates, amber/red for wanted plates.
class AppColors {
  AppColors._();

  static const Color background = Color(0xFF0B132B);
  static const Color backgroundAlt = Color(0xFF1C2541);
  static const Color card = Color(0xFF1C2D42);
  static const Color cardBorder = Color(0xFF2A3B55);

  static const Color textPrimary = Color(0xFFF5F7FA);
  static const Color textSecondary = Color(0xFFA9B4C5);

  static const Color success = Color(0xFF00E676); // سليمة / clear
  static const Color danger = Color(0xFFFF3D00); // مطلوبة / wanted alert
  static const Color accentBlue = Color(0xFF4C6FFF);
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      
      colorScheme: const ColorScheme.dark(
        primary: AppColors.accentBlue,
        secondary: AppColors.success,
        error: AppColors.danger,
        surface: AppColors.card,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          
        ),
      ),
      cardColor: AppColors.card,
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.backgroundAlt,
        selectedItemColor: AppColors.success,
        unselectedItemColor: AppColors.textSecondary,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
          
        ),
        titleMedium: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
          
        ),
        bodyMedium: TextStyle(
          color: AppColors.textSecondary,
          
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentBlue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          textStyle: const TextStyle(
            
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
