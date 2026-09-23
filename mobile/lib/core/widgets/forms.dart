import 'package:flutter/material.dart';

import '../format.dart';
import '../theme.dart';

/// A text input with its label above it, the way the dashboard's forms read.
///
/// Label above rather than floating inside: several of these are paragraphs a
/// specialist writes to a parent, and a label that shrinks into the border as
/// soon as she starts typing is a label she can no longer see.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.help,
    this.error,
    this.required = false,
    this.maxLines = 1,
    this.minLines,
    this.keyboardType,
    this.ltr = false,
    this.obscure = false,
    this.onChanged,
    this.textInputAction,
    this.autofillHints,
    this.enabled = true,
    this.maxLength,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;

  /// A line under the label saying why the field matters.
  final String? help;
  final String? error;
  final bool required;
  final int maxLines;
  final int? minLines;
  final TextInputType? keyboardType;

  /// Emails, phones, numbers.
  final bool ltr;
  final bool obscure;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool enabled;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            text: label,
            children: [
              if (required) const TextSpan(text: ' *', style: TextStyle(color: AppColors.bad)),
            ],
          ),
          style: text.labelLarge,
        ),
        if (help != null) Text(help!, style: text.bodySmall),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: enabled,
          maxLines: obscure ? 1 : maxLines,
          minLines: minLines,
          maxLength: maxLength,
          keyboardType: keyboardType ?? (maxLines > 1 ? TextInputType.multiline : null),
          textDirection: ltr ? TextDirection.ltr : null,
          textAlign: TextAlign.start,
          obscureText: obscure,
          onChanged: onChanged,
          textInputAction: textInputAction,
          autofillHints: autofillHints,
          style: text.bodyLarge,
          decoration: InputDecoration(hintText: hint, errorText: error, errorMaxLines: 3),
        ),
      ],
    );
  }
}

/// A tappable field that opens the date picker.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.required = false,
    this.first,
    this.last,
    this.error,
    this.clearable = false,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool required;
  final DateTime? first;
  final DateTime? last;
  final String? error;
  final bool clearable;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            text: label,
            children: [if (required) const TextSpan(text: ' *', style: TextStyle(color: AppColors.bad))],
          ),
          style: text.labelLarge,
        ),
        const SizedBox(height: 6),
        InkWell(
          borderRadius: AppShape.control,
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: value ?? now,
              firstDate: first ?? DateTime(now.year - 25),
              lastDate: last ?? DateTime(now.year + 3),
            );
            if (picked != null) onChanged(picked);
          },
          child: InputDecorator(
            decoration: InputDecoration(
              errorText: error,
              suffixIcon: clearable && value != null
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => onChanged(null),
                    )
                  : const Icon(Icons.calendar_month_rounded, size: 20, color: AppColors.muted),
            ),
            child: Text(
              value == null ? 'اختر التاريخ' : Fmt.date(Fmt.isoDate(value!)),
              style: text.bodyLarge?.copyWith(color: value == null ? AppColors.faint : null),
            ),
          ),
        ),
      ],
    );
  }
}

/// One choice out of a few, as chips — faster to hit on a phone than a menu.
class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.label,
    this.required = false,
  });

  final List<(T, String)> options;
  final T? selected;
  final ValueChanged<T> onSelected;
  final String? label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null) ...[
          Text.rich(
            TextSpan(
              text: label,
              children: [if (required) const TextSpan(text: ' *', style: TextStyle(color: AppColors.bad))],
            ),
            style: text.labelLarge,
          ),
          const SizedBox(height: 6),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (value, name) in options)
              ChoiceChip(
                label: Text(name),
                selected: selected == value,
                onSelected: (_) => onSelected(value),
                labelStyle: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: selected == value ? AppColors.brand : AppColors.inkSoft,
                ),
                side: BorderSide(color: selected == value ? AppColors.brand : AppColors.line),
              ),
          ],
        ),
      ],
    );
  }
}

/// A form in a bottom sheet: title, scrolling fields, one button pinned
/// above the keyboard.
Future<T?> showFormSheet<T>(BuildContext context, {required Widget Function(BuildContext) builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: builder,
  );
}

class FormSheet extends StatelessWidget {
  const FormSheet({
    super.key,
    required this.title,
    required this.children,
    required this.submitLabel,
    required this.onSubmit,
    this.busy = false,
    this.subtitle,
    this.error,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final String submitLabel;
  final VoidCallback? onSubmit;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final inset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleLarge),
                  if (subtitle != null) Text(subtitle!, style: text.bodySmall),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                children: [
                  for (final child in children) ...[child, const SizedBox(height: 14)],
                ],
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(error!, style: const TextStyle(fontFamily: 'Cairo', color: AppColors.bad, fontWeight: FontWeight.w600)),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: FilledButton(
                  onPressed: busy ? null : onSubmit,
                  child: busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                        )
                      : Text(submitLabel),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A trimmed value, or null when empty — what a `nullable` rule expects.
String? nullIfEmpty(TextEditingController controller) {
  final value = controller.text.trim();
  return value.isEmpty ? null : value;
}
