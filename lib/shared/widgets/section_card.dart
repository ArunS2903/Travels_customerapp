import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';

/// A titled card. Used for every block on the confirmation and details screens
/// so they read as one consistent document rather than a pile of containers.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.icon,
    this.trailing,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  final Widget child;
  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Expanded(child: Text(title!, style: theme.textTheme.titleSmall)),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// A label/value row, the workhorse of the summary screens.
///
/// The value wraps and is right-aligned, so a long address does not push the
/// label off the screen or get silently truncated.
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.valueWidget,
    this.icon,
    this.emphasised = false,
    this.valueColor,
  });

  final String label;
  final String value;

  /// Replaces the value text, for a chip or a formatted amount.
  final Widget? valueWidget;

  final IconData? icon;

  /// Bolder, larger type for the one row that matters most, e.g. the total.
  final bool emphasised;

  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: emphasised
                  ? theme.textTheme.titleSmall
                  : theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            flex: 6,
            child: valueWidget ??
                Text(
                  value,
                  textAlign: TextAlign.right,
                  style: emphasised
                      ? theme.textTheme.titleMedium?.copyWith(color: valueColor)
                      : theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: valueColor,
                        ),
                ),
          ),
        ],
      ),
    );
  }
}

/// Pickup and destination with the dot-line-pin connector, which is how a rider
/// reads a trip at a glance. Used on the home, confirmation and details screens.
class RouteSummary extends StatelessWidget {
  const RouteSummary({
    super.key,
    required this.pickupAddress,
    required this.destinationAddress,
    this.pickupLabel = 'Pickup',
    this.destinationLabel = 'Destination',
    this.onTapPickup,
    this.onTapDestination,
    this.dense = false,
  });

  final String pickupAddress;
  final String destinationAddress;
  final String pickupLabel;
  final String destinationLabel;
  final VoidCallback? onTapPickup;
  final VoidCallback? onTapDestination;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The connector: a hollow circle, a dashed run, a solid pin.
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            children: [
              Container(
                height: 11,
                width: 11,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.colorScheme.onSurfaceVariant, width: 2.2),
                ),
              ),
              _DottedLine(height: dense ? 22 : 30, color: theme.colorScheme.outline),
              Icon(Icons.place_rounded, size: 15, color: theme.colorScheme.error),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AddressLine(
                label: pickupLabel,
                address: pickupAddress,
                onTap: onTapPickup,
                dense: dense,
              ),
              SizedBox(height: dense ? AppSpacing.md : AppSpacing.lg),
              _AddressLine(
                label: destinationLabel,
                address: destinationAddress,
                onTap: onTapDestination,
                dense: dense,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AddressLine extends StatelessWidget {
  const _AddressLine({
    required this.label,
    required this.address,
    required this.dense,
    this.onTap,
  });

  final String label;
  final String address;
  final bool dense;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!dense) Text(label, style: theme.textTheme.labelSmall),
        Text(
          address.isEmpty ? 'Not set' : address,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
            color: address.isEmpty ? theme.colorScheme.onSurfaceVariant : null,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );

    if (onTap == null) return content;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: content),
    );
  }
}

/// Vertical dashed line drawn with a custom painter, so it scales with the text
/// rather than being a fixed-size image.
class _DottedLine extends StatelessWidget {
  const _DottedLine({required this.height, required this.color});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: 11,
      child: CustomPaint(painter: _DottedLinePainter(color)),
    );
  }
}

class _DottedLinePainter extends CustomPainter {
  const _DottedLinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const dash = 3.0;
    const gap = 3.5;
    double y = 2;

    while (y < size.height - 2) {
      canvas.drawLine(
        Offset(size.width / 2, y),
        Offset(size.width / 2, (y + dash).clamp(0, size.height - 2)),
        paint,
      );
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DottedLinePainter oldDelegate) => oldDelegate.color != color;
}
