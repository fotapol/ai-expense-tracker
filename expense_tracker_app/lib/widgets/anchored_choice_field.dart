import 'package:flutter/material.dart';

import '../core/redesign_system.dart';

/// A controlled choice field. Its menu attaches below the field, with a bounded
/// scrolling list; Flutter can place it above when the viewport has no room.
class AnchoredChoiceField extends StatelessWidget {
  const AnchoredChoiceField({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.label,
  });

  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final radius = BorderRadius.circular(12);
      final tone = ShellStyles.accentTone(context);
      return MenuAnchor(
        alignmentOffset: const Offset(0, 6),
        crossAxisUnconstrained: false,
        consumeOutsideTap: true,
        clipBehavior: Clip.antiAlias,
        style: MenuStyle(
          alignment: AlignmentDirectional.bottomStart,
          minimumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, 0)),
          maximumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, 260)),
          backgroundColor: WidgetStatePropertyAll(ShellStyles.surface(context)),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: radius),
          ),
        ),
        menuChildren: [
          for (final option in options.entries)
            MenuItemButton(
              onPressed: () => onChanged(option.key),
              style: MenuItemButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                foregroundColor: option.key == value
                    ? tone.foreground
                    : ShellStyles.textPrimary(context),
                backgroundColor: option.key == value
                    ? tone.container
                    : Colors.transparent,
              ),
              leadingIcon: option.key == value
                  ? const Icon(Icons.check, size: 18)
                  : const SizedBox(width: 18),
              child: Text(option.value, style: const TextStyle(fontSize: 13)),
            ),
        ],
        builder: (context, controller, child) => Semantics(
          button: true,
          expanded: controller.isOpen,
          child: Material(
            color: ShellStyles.surfaceAlt(context),
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              borderRadius: radius,
              onTap: () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  FocusManager.instance.primaryFocus?.unfocus();
                  controller.open();
                }
              },
              child: InputDecorator(
                isFocused: controller.isOpen,
                decoration: InputDecoration(
                  labelText: label,
                  isDense: true,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(borderRadius: radius),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: radius,
                    borderSide: BorderSide(color: ShellStyles.border(context)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        options[value] ?? '',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.expand_more, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
