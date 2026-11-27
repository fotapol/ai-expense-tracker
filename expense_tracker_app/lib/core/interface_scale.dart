import 'dart:ui' show DisplayFeature;

import 'package:flutter/material.dart';

/// Changes layout coordinates as well as painting. Smaller percentages provide
/// more layout space, so controls can reflow instead of only shrinking text.
/// Platform text accessibility and physical system insets remain independent.
class InterfaceScale extends StatelessWidget {
  const InterfaceScale({super.key, required this.factor, required this.child});

  final double factor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    assert(factor.isFinite && factor > 0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.of(context);
        final size = constraints.biggest / factor;
        return FittedBox(
          fit: BoxFit.fill,
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: size,
            child: MediaQuery(
              data: media.copyWith(
                size: size,
                devicePixelRatio: media.devicePixelRatio * factor,
                padding: media.padding / factor,
                viewPadding: media.viewPadding / factor,
                viewInsets: media.viewInsets / factor,
                systemGestureInsets: media.systemGestureInsets / factor,
                displayFeatures: [
                  for (final feature in media.displayFeatures)
                    DisplayFeature(
                      bounds: Rect.fromLTRB(
                        feature.bounds.left / factor,
                        feature.bounds.top / factor,
                        feature.bounds.right / factor,
                        feature.bounds.bottom / factor,
                      ),
                      type: feature.type,
                      state: feature.state,
                    ),
                ],
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
