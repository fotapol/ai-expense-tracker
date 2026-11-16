import 'dart:math' as math;

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
      final field = MenuAnchor(
        alignmentOffset: const Offset(0, 6),
        crossAxisUnconstrained: false,
        consumeOutsideTap: true,
        clipBehavior: Clip.antiAlias,
        style: MenuStyle(
          alignment: AlignmentDirectional.bottomStart,
          minimumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, 0)),
          maximumSize: WidgetStateProperty.resolveWith((states) {
            // Resolve on opening, once the field has a position. Bound the menu
            // by the larger free side so a short/keyboard viewport does not
            // force the panel over its anchor.
            final box = context.findRenderObject() as RenderBox?;
            final overlay =
                Overlay.of(context).context.findRenderObject() as RenderBox?;
            var height = 260.0;
            if (box != null &&
                box.hasSize &&
                overlay != null &&
                overlay.hasSize) {
              final media = MediaQuery.of(context);
              final top = box.localToGlobal(Offset.zero, ancestor: overlay).dy;
              final bottom = box
                  .localToGlobal(Offset(0, box.size.height), ancestor: overlay)
                  .dy;
              final above = top - media.viewPadding.top - 12;
              final below =
                  overlay.size.height -
                  math.max(media.viewInsets.bottom, media.viewPadding.bottom) -
                  bottom -
                  12;
              height = math
                  .min(height, math.max(above, below))
                  .clamp(0.0, 260.0);
            }
            return Size(constraints.maxWidth, height);
          }),
          backgroundColor: WidgetStatePropertyAll(ShellStyles.surface(context)),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          side: WidgetStatePropertyAll(
            BorderSide(color: ShellStyles.border(context)),
          ),
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
          label: label,
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
      if (label == null) return field;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, bottom: 6),
            child: ExcludeSemantics(
              child: Text(
                label!,
                style: TextStyle(
                  color: ShellStyles.textMuted(context),
                  fontSize: 12,
                ),
              ),
            ),
          ),
          field,
        ],
      );
    },
  );
}
