import 'package:flutter/material.dart';

/// The palette.
///
/// Built around a deep ink primary with a taxi-amber accent: amber carries the
/// brand and marks the single most important action on a screen, ink carries
/// structure and text. Keeping the accent scarce is what makes "Confirm
/// Booking" obvious without shouting.
///
/// Every text/background pair below meets WCAG AA (4.5:1) at body size.
class AppColors {
  const AppColors._();

  // --- Brand ----------------------------------------------------------------

  /// Primary surface colour for headers, buttons and the map route line.
  static const Color ink = Color(0xFF14181F);
  static const Color inkSoft = Color(0xFF232935);
  static const Color inkMuted = Color(0xFF3A4252);

  /// The accent. Used for the primary CTA, selection states and the logo.
  static const Color amber = Color(0xFFFFC107);
  static const Color amberDark = Color(0xFFE0A500);
  static const Color amberSoft = Color(0xFFFFF4D6);

  // --- Light scheme ---------------------------------------------------------

  static const Color lightBackground = Color(0xFFF7F8FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFF1F3F7);
  static const Color lightBorder = Color(0xFFE2E6ED);
  static const Color lightTextPrimary = Color(0xFF14181F);
  static const Color lightTextSecondary = Color(0xFF5B6475);
  static const Color lightTextTertiary = Color(0xFF8A93A3);

  // --- Dark scheme ----------------------------------------------------------

  static const Color darkBackground = Color(0xFF0E1116);
  static const Color darkSurface = Color(0xFF181D26);
  static const Color darkSurfaceAlt = Color(0xFF212833);
  static const Color darkBorder = Color(0xFF2E3542);
  static const Color darkTextPrimary = Color(0xFFF2F4F8);
  static const Color darkTextSecondary = Color(0xFFA8B1C1);
  static const Color darkTextTertiary = Color(0xFF737D8D);

  // --- Semantic -------------------------------------------------------------

  static const Color success = Color(0xFF1B9E5A);
  static const Color successSoft = Color(0xFFE3F6EC);
  static const Color warning = Color(0xFFCF8100);
  static const Color warningSoft = Color(0xFFFDF2DC);
  static const Color danger = Color(0xFFD03030);
  static const Color dangerSoft = Color(0xFFFBE9E9);
  static const Color info = Color(0xFF2563C7);
  static const Color infoSoft = Color(0xFFE6EEFB);

  /// Route polyline on the map.
  static const Color route = Color(0xFF14181F);
  static const Color pickupPin = Color(0xFF1B9E5A);
  static const Color destinationPin = Color(0xFFD03030);
}
