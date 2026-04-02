import 'package:flutter/material.dart';

import '../core/redesign_system.dart';
import 'receipt_upload_screen.dart';

class SettingsDetailScaffold extends StatelessWidget {
  const SettingsDetailScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.showScanAction = false,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final bool showScanAction;

  Future<void> _openScan(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ReceiptUploadScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShellStyles.background(context),
      appBar: AppBar(
        title: Text(
          title,
          style: TextStyle(
            color: ShellStyles.textPrimary(context),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: actions,
      ),
      body: body,
      floatingActionButton: showScanAction
          ? FloatingActionButton(
              onPressed: () => _openScan(context),
              backgroundColor: ShellStyles.textPrimary(context),
              foregroundColor: ShellStyles.surface(context),
              shape: const CircleBorder(),
              child: const Icon(AppIcons.scanFab),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

class SettingsDetailCard extends StatelessWidget {
  const SettingsDetailCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = 18,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: ShellStyles.cardDecoration(context, radius: radius),
      child: child,
    );
  }
}

class SettingsSearchField extends StatelessWidget {
  const SettingsSearchField({
    super.key,
    required this.hintText,
    required this.onChanged,
  });

  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(AppIcons.search),
        isDense: true,
        filled: true,
        fillColor: ShellStyles.surface(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: ShellStyles.border(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: ShellStyles.border(context)),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
    );
  }
}

class SettingsChoiceRow extends StatelessWidget {
  const SettingsChoiceRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.selectedBorder = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  final bool selectedBorder;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final borderColor = selectedBorder
        ? ShellStyles.textPrimary(context)
        : ShellStyles.border(context);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: ShellStyles.surface(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: ShellStyles.textPrimary(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: ShellStyles.textMuted(context),
                        fontSize: 11.5,
                        height: 1.25,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            trailing ??
                (selected
                    ? Icon(
                        AppIcons.check,
                        color: ShellStyles.textPrimary(context),
                      )
                    : const SizedBox.shrink()),
          ],
        ),
      ),
    );
  }
}

class SettingsToggleRow extends StatelessWidget {
  const SettingsToggleRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: ShellStyles.textPrimary(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: ShellStyles.textMuted(context),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => onChanged(!value),
            child: _OutlinedSwitch(value: value),
          ),
        ],
      ),
    );
  }
}

class _OutlinedSwitch extends StatelessWidget {
  const _OutlinedSwitch({required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 50,
      height: 28,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: value
            ? ShellStyles.textPrimary(context)
            : ShellStyles.border(context),
        borderRadius: BorderRadius.circular(999),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 180),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: ShellStyles.surface(context),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
