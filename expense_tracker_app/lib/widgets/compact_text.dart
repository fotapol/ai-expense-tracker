import 'package:flutter/material.dart';

class CompactText extends StatelessWidget {
  const CompactText(
    this.data, {
    super.key,
    this.style,
    this.textAlign = TextAlign.center,
  });

  final String data;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: Text(
        data,
        maxLines: 1,
        overflow: TextOverflow.visible,
        softWrap: false,
        textAlign: textAlign,
        style: style,
      ),
    );
  }
}
