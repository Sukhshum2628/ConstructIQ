import 'package:flutter/material.dart';
import '../utils/design_tokens.dart';

class DFCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final double? borderRadius;
  final bool hasShadow;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const DFCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.color,
    this.borderRadius,
    this.hasShadow = true,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cardBody = Container(
      decoration: BoxDecoration(
        color: color ?? DFColors.surface,
        borderRadius: BorderRadius.circular(borderRadius ?? 12.0),
        boxShadow: hasShadow 
          ? [
              BoxShadow(
                color: DFColors.textPrimary.withValues(alpha: 0.06),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ]
          : null,
      ),
      padding: padding ?? const EdgeInsets.all(DFSpacing.md),
      margin: margin,
      child: child,
    );

    if (onTap != null || onLongPress != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(borderRadius ?? 12.0),
          splashColor: DFColors.primary.withValues(alpha: 0.05),
          highlightColor: DFColors.primary.withValues(alpha: 0.02),
          child: cardBody,
        ),
      );
    }

    return cardBody;
  }
}
