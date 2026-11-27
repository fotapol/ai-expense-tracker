import 'package:flutter/widgets.dart';

/// Retains a visited PageView tab, including data and its scroll position.
class KeepAliveTab extends StatefulWidget {
  const KeepAliveTab({super.key, required this.child});
  final Widget child;

  @override
  State<KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
