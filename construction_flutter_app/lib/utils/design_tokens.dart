import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class DFColors {
  // Primary
  static const primary = Color(0xFF1A56A0);
  static const primaryDark = Color(0xFF0D3470);
  static const primaryLight = Color(0xFFEFF6FF);

  // Severity
  static const critical = Color(0xFFDC2626);
  static const criticalBg = Color(0xFFFEE2E2);
  static const warning = Color(0xFFD97706);
  static const warningBg = Color(0xFFFEF3C7);
  static const normal = Color(0xFF16A34A);
  static const normalBg = Color(0xFFDCFCE7);
  static const success = Color(0xFF16A34A);
  static const successBg = Color(0xFFDCFCE7);

  // Neutrals
  static const background = Color(0xFFF7F9FC); // Updated to Stitch exact
  static const surface = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF191C1E); // on-surface
  static const textSecondary = Color(0xFF424751); // on-surface-variant
  static const textCaption = Color(0xFF9CA3AF);
  static const divider = Color(0xFFE5E7EB);
  
  // Stitch specific
  static const primaryStitch = Color(0xFF003E7E);
  static const primaryContainerStitch = Color(0xFF1A56A0);
  static const surfaceContainerHighest = Color(0xFFE0E3E6);
  static const surfaceContainerHigh = Color(0xFFE6E8EB);
  static const outline = Color(0xFF737782);
  static const outlineVariant = Color(0xFFC2C6D3);
  static const surfaceContainerLow = Color(0xFFF2F4F7);
  static const surfaceContainerLowest = Color(0xFFFFFFFF);
  static const onPrimary = Color(0xFFFFFFFF);
  static const primaryFixed = Color(0xFFD6E3FF);
  static const primaryContainer = Color(0xFF1A56A0);
  static const secondaryContainer = Color(0xFFFEA619);

  // Accent
  static const accent = Color(0xFFF59E0B);
  static const secondary = Color(0xFF855300);
}

class DFTextStyles {
  // Base Inter font family
  static final String? _fontFamily = GoogleFonts.inter().fontFamily;

  static TextStyle screenTitle = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 24, 
    fontWeight: FontWeight.w700, 
    color: DFColors.textPrimary,
    height: 1.25,
  );

  static TextStyle headline = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 24, 
    fontWeight: FontWeight.w700, 
    color: DFColors.textPrimary,
    height: 1.25,
  );
  
  static TextStyle sectionHeader = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16, 
    fontWeight: FontWeight.w600, 
    color: DFColors.primary,
    height: 1.25,
  );
  
  static TextStyle cardTitle = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16, 
    fontWeight: FontWeight.w700, 
    color: DFColors.textPrimary,
    height: 1.25,
  );
  
  static TextStyle cardSubtitle = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 13, 
    fontWeight: FontWeight.w400, 
    color: DFColors.textSecondary,
    height: 1.3,
  );
  
  static TextStyle metricHero = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 44, 
    fontWeight: FontWeight.w700, 
    color: DFColors.textPrimary,
    height: 1.1,
  );
  
  static TextStyle metricLarge = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 28, 
    fontWeight: FontWeight.w700, 
    color: DFColors.textPrimary,
    height: 1.1,
  );
  
  static TextStyle caption = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12, 
    fontWeight: FontWeight.w400, 
    color: DFColors.textCaption,
    height: 1.3,
  );
  
  static TextStyle body = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14, 
    fontWeight: FontWeight.w400, 
    color: DFColors.textPrimary,
    height: 1.4, // Slightly more for body readability
  );
  
  static TextStyle labelSm = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: DFColors.textSecondary,
    height: 1.2,
  );
}

class DFSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}
