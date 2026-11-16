import 'package:flutter/material.dart';

import '../core/app_motion.dart';

/// Keeps each root tab mounted while sliding between their layout positions.
/// Hidden pages cannot take focus, pointer events or accessibility traversal.
class SlidingTabView extends StatefulWidget {
  const SlidingTabView({super.key, required this.index, required this.children})
    : assert(index >= 0 && index < children.length);

  final int index;
  final List<Widget> children;

  @override
  State<SlidingTabView> createState() => _SlidingTabViewState();
}

class _SlidingTabViewState extends State<SlidingTabView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _position = AnimationController.unbounded(
    vsync: this,
    value: widget.index.toDouble(),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _position.value = widget.index.toDouble();
    }
  }

  @override
  void didUpdateWidget(SlidingTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index == oldWidget.index) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _position.value = widget.index.toDouble();
    } else {
      _position.animateTo(
        widget.index.toDouble(),
        duration: AppMotion.duration(context),
        curve: AppMotion.curve,
      );
    }
  }

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context) == TextDirection.rtl ? -1 : 1;
    return ClipRect(
      child: AnimatedBuilder(
        animation: _position,
        builder: (context, child) => Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < widget.children.length; i++)
              Offstage(
                offstage: (i - _position.value).abs() >= 1,
                child: TickerMode(
                  enabled: i == widget.index,
                  child: ExcludeFocus(
                    excluding: i != widget.index,
                    child: ExcludeSemantics(
                      excluding: i != widget.index,
                      child: IgnorePointer(
                        ignoring: i != widget.index,
                        child: FractionalTranslation(
                          translation: Offset(
                            (i - _position.value) * direction,
                            0,
                          ),
                          child: widget.children[i],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
