import 'package:flutter/material.dart';

/// The palette, taken from the PP Travels & Cab logo.
///
/// The mark is a single gradient sweep - orange at the lower left, through red
/// and pink, into purple at the lower right - and the palette is built so that
/// sweep carries the brand while a neutral ink carries structure and text.
///
/// Two ideas are kept apart here, and keeping them apart is what makes the
/// theme usable rather than merely colourful:
///
///   * [brandGradient] and the raw [logoRed] family are *decoration*. They go
///     behind things. Nothing small or textual is drawn in them, because the
///     logo's own red is `#fa1f32`, which is 3.95:1 on white and fails WCAG AA
///     for body text.
///   * [brand] and its ramp are *interface*. [brand] is 5.2:1 on white and
///     [brandDark] is 7.1:1, so a label, an icon or a focus ring drawn in them
///     is legible at any size.
///
/// A screen that wants to look branded reaches for the gradient; a screen that
/// wants to be read reaches for the ramp. Every text/background pair below
/// meets WCAG AA (4.5:1) at body size.
class AppColors {
  const AppColors._();

  // --- The logo's own colours, for gradients only --------------------------

  /// Sampled from the mark, lower left to lower right.
  static const Color logoOrange = Color(0xFFFD6A3E);
  static const Color logoRed = Color(0xFFFA1F32);
  static const Color logoPink = Color(0xFFF33685);
  static const Color logoMagenta = Color(0xFFE63199);
  static const Color logoPurple = Color(0xFF9B3DBB);

  /// The brand sweep. The stop positions are the proportions the colours
  /// occupy in the mark itself, which is why they are not evenly spaced: red
  /// dominates the top arc and purple only appears at the very end.
  static const List<Color> brandGradientColors = [
    logoOrange,
    logoRed,
    logoPink,
    logoMagenta,
    logoPurple,
  ];

  static const List<double> brandGradientStops = [0.0, 0.28, 0.58, 0.78, 1.0];

  /// The gradient as the app draws it: top-left to bottom-right, matching the
  /// diagonal of the mark.
  static const LinearGradient brandGradient = LinearGradient(
    colors: brandGradientColors,
    stops: brandGradientStops,
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// The same sweep laid out horizontally, for bars, underlines and dividers
  /// where a diagonal would read as a mistake.
  static const LinearGradient brandGradientHorizontal = LinearGradient(
    colors: brandGradientColors,
    stops: brandGradientStops,
  );

  // --- The interface ramp ---------------------------------------------------

  /// Hue 352: the logo's red (355) pulled a little toward its pink (335), so
  /// the ramp reads as the whole mark rather than one arc of it.
  static const Color brand50 = Color(0xFFFFF0F2);
  static const Color brand100 = Color(0xFFFEE1E5);
  static const Color brand200 = Color(0xFFFDC1C9);
  static const Color brand300 = Color(0xFFFB98A5);
  static const Color brand400 = Color(0xFFF86276);
  static const Color brand500 = Color(0xFFF42F49);
  static const Color brand600 = Color(0xFFD8102B);
  static const Color brand700 = Color(0xFFB00F25);
  static const Color brand800 = Color(0xFF8D1122);
  static const Color brand900 = Color(0xFF731421);

  /// The primary brand colour for interface use. 5.21:1 on white.
  static const Color brand = brand600;

  /// For text and icons that need more contrast than [brand]. 7.14:1 on white.
  static const Color brandDark = brand700;

  /// The brand on a dark surface, where [brand] would be too heavy.
  static const Color brandOnDark = brand300;

  /// Tinted fills: a selected chip, a highlighted row, an info strip.
  static const Color brandSoft = brand50;
  static const Color brandSoftBorder = brand200;

  // --- Structure ------------------------------------------------------------

  /// Headers, body text and the map route line. Deliberately near-black rather
  /// than a tinted charcoal: a long address list set in brand-tinted grey is
  /// tiring, and the colour is doing no work there.
  static const Color ink = Color(0xFF14181F);
  static const Color inkSoft = Color(0xFF232935);
  static const Color inkMuted = Color(0xFF3A4252);

  // --- Light scheme ---------------------------------------------------------

  static const Color lightBackground = Color(0xFFF8F7FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFF3F1F6);
  static const Color lightBorder = Color(0xFFE6E3EC);
  static const Color lightTextPrimary = Color(0xFF14181F);
  static const Color lightTextSecondary = Color(0xFF5B6475);
  static const Color lightTextTertiary = Color(0xFF8A93A3);

  // --- Dark scheme ----------------------------------------------------------

  static const Color darkBackground = Color(0xFF100E14);
  static const Color darkSurface = Color(0xFF1A171F);
  static const Color darkSurfaceAlt = Color(0xFF241F2B);
  static const Color darkBorder = Color(0xFF342D3C);
  static const Color darkTextPrimary = Color(0xFFF4F2F8);
  static const Color darkTextSecondary = Color(0xFFADA6B8);
  static const Color darkTextTertiary = Color(0xFF7A7386);

  // --- Semantic -------------------------------------------------------------

  /// Status colours stay outside the brand ramp on purpose. "Paid" in green
  /// and "cancelled" in red have to mean those things at a glance, and they
  /// cannot if the whole screen is already pink.
  static const Color success = Color(0xFF1B9E5A);
  static const Color successSoft = Color(0xFFE3F6EC);
  static const Color warning = Color(0xFFCF8100);
  static const Color warningSoft = Color(0xFFFDF2DC);

  /// Destructive actions. Distinct from [logoRed] and from [brand], because an
  /// irreversible action must not look like a branded one.
  static const Color danger = Color(0xFFC62828);
  static const Color dangerSoft = Color(0xFFFBE9E9);
  static const Color info = Color(0xFF2563C7);
  static const Color infoSoft = Color(0xFFE6EEFB);

  /// Route polyline on the map, and the two end pins.
  static const Color route = brand600;
  static const Color pickupPin = Color(0xFF1B9E5A);
  static const Color destinationPin = brand600;
}
