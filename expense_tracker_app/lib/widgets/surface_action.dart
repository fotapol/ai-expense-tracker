import 'package:flutter/material.dart';

import '../core/redesign_system.dart';

/// A card whose ink feedback is painted and clipped on its own material.
class SurfaceAction extends StatelessWidget {
  const SurfaceAction({
    super.key,
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.radius = 16,
    this.padding = const EdgeInsets.all(12),
    this.highlighted = false,
  });

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final tone = ShellStyles.accentTone(context);
    return DecoratedBox(
      decoration: ShellStyles.cardDecoration(context, radius: radius),
      child: Material(
        color: ShellStyles.surface(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(
            color: highlighted ? tone.border : ShellStyles.border(context),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
