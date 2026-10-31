/// Spacing, radius and elevation scale.
///
/// A fixed 4pt scale rather than ad-hoc numbers: it is what keeps a dozen
/// screens written at different times looking like one app.
class AppSpacing {
  const AppSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;

  /// Horizontal page gutter. Used by every screen so content lines up.
  static const double pageGutter = 20;

  /// Minimum tap target, per Material and WCAG guidance.
  static const double minTapTarget = 48;
}

class AppRadius {
  const AppRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double pill = 999;

  /// Bottom sheets and the map's draw-up panel.
  static const double sheet = 24;
}
