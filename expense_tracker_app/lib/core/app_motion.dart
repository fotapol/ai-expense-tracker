import 'package:flutter/material.dart';

abstract final class AppMotion {
  static const curve = Curves.easeInOutCubic;
  static Duration duration(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 320);
}

class AppPageTransitionsBuilder extends FadeForwardsPageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      (context, animation, secondaryAnimation, allowSnapshotting, child) =>
          MediaQuery.disableAnimationsOf(context)
          ? child
          : super.delegatedTransition!(
              context,
              animation,
              secondaryAnimation,
              allowSnapshotting,
              child,
            );

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext? context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => context != null && MediaQuery.disableAnimationsOf(context)
      ? child
      : super.buildTransitions(
          route,
          context,
          animation,
          secondaryAnimation,
          child,
        );
}
