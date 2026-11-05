import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import 'office_data.dart';
import 'staff_form.dart';

/// Linking a family to a child's file.
///
/// Two steps that look like one: the guardian needs an account before she can
/// be linked, and the account is made here rather than on the staff screen —
/// because the office is standing in front of a father at enrolment, not
/// administering a directory.
///
/// Resolves to true when something was linked.
Future<bool?> openGuardianPicker(BuildContext context, WidgetRef ref, Student student) {
  return showFormSheet<bool>(
    context,
    builder: (_) => _GuardianPicker(student: student),
  );
}

class _GuardianPicker extends ConsumerStatefulWidget {
  const _GuardianPicker({required this.student});

  final Student student;

  @override
  ConsumerState<_GuardianPicker> createState() => _GuardianPickerState();
}

class _GuardianPickerState extends ConsumerState<_GuardianPicker> {
  final _search = TextEditingController();

  String _query = '';
  Timer? _debounce;
  int? _picked;
  String _relation = 'father';
  bool _primary = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onTyped(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  Future<void> _link() async {
    if (_picked == null) {
      setState(() => _error = 'اختر الحساب أولاً.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(apiProvider).post('/students/${widget.student.id}/guardians', body: {
        'user_id': _picked,
        'relation': _relation,
        'is_primary': _primary,
      });

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final guardians = ref.watch(
      staffProvider((role: 'guardian', search: _query, active: null)),
    );
    final text = Theme.of(context).textTheme;

    return FormSheet(
      title: 'اربط ولي أمر',
      subtitle: widget.student.name,
      submitLabel: 'اربط',
      busy: _busy,
      error: _error,
      onSubmit: _link,
      children: [
        TextField(
          controller: _search,
          onChanged: _onTyped,
          decoration: const InputDecoration(
            hintText: 'ابحث باسم ولي الأمر أو بريده…',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),

        guardians.when(
          loading: () => const AppLoading(),
          error: (error, _) => AppError(
            error: error,
            onRetry: () => reload(
              ref,
              staffProvider((role: 'guardian', search: _query, active: null)).future,
            ),
          ),
          data: (list) => list.isEmpty
              ? Column(
                  children: [
                    const NoteBox(
                      'ما في حساب ولي أمر بهذا الاسم. افتح حساباً جديداً وبعدين اربطه.',
                      tone: 'warn',
                      icon: Icons.person_search_rounded,
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final created = await openStaffForm(context, ref, fixedRole: 'guardian');
                        if (created == null || !mounted) return;
                        setState(() {
                          _picked = created.id;
                          _search.text = created.name;
                          _query = created.name;
                        });
                      },
                      icon: const Icon(Icons.person_add_alt_rounded),
                      label: const Text('حساب ولي أمر جديد'),
                    ),
                  ],
                )
              : Column(
                  children: [
                    for (final account in list.take(8))
                      // A tappable row rather than `RadioListTile`: the radio
                      // group API moved in Flutter 3.32 and the selected row
                      // reads better with the brand tick anyway.
                      ListTile(
                        onTap: () => setState(() => _picked = account.id),
                        contentPadding: EdgeInsets.zero,
                        leading: Avatar(name: account.name, seed: account.id, size: 38),
                        title: Text(account.name, style: text.titleSmall),
                        subtitle: Text(
                          [account.email, if (account.phone != null) account.phone!].join(' · '),
                          style: text.bodySmall,
                        ),
                        trailing: Icon(
                          _picked == account.id
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: _picked == account.id ? AppColors.brand : AppColors.faint,
                        ),
                      ),
                  ],
                ),
        ),

        ChoiceRow<String>(
          label: 'صلة القرابة',
          required: true,
          selected: _relation,
          options: [for (final e in Labels.relation.entries) (e.key, e.value)],
          onSelected: (value) => setState(() => _relation = value),
        ),

        SwitchListTile(
          value: _primary,
          onChanged: (value) => setState(() => _primary = value),
          contentPadding: EdgeInsets.zero,
          title: const Text('جهة الاتصال الأولى'),
          // One per child, enforced on the server — switching this on moves
          // it off whoever had it rather than creating a second.
          subtitle: const Text('بيصير هو أول من نتصل فيه، وبينشال عن غيره.'),
        ),
      ],
    );
  }
}
