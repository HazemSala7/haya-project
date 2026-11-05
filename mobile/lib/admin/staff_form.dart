import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';

/// Opening and editing an account — staff or family.
///
/// One form for both because the server has one endpoint and one validation:
/// role decides which fields matter, not which screen you came from. A parent
/// account made on the students screen and a specialist made here are the same
/// row, and two forms would be two chances to disagree about it.
///
/// [fixedRole] locks the role — used when the office is standing in front of a
/// father and needs a guardian account, not a role picker.
Future<Account?> openStaffForm(
  BuildContext context,
  WidgetRef ref, {
  Account? account,
  String? fixedRole,
}) {
  return showFormSheet<Account>(
    context,
    builder: (_) => _StaffForm(account: account, fixedRole: fixedRole),
  );
}

class _StaffForm extends ConsumerStatefulWidget {
  const _StaffForm({this.account, this.fixedRole});

  final Account? account;
  final String? fixedRole;

  @override
  ConsumerState<_StaffForm> createState() => _StaffFormState();
}

class _StaffFormState extends ConsumerState<_StaffForm> {
  late final _name = TextEditingController(text: widget.account?.name ?? '');
  late final _email = TextEditingController(text: widget.account?.email ?? '');
  late final _phone = TextEditingController(text: widget.account?.phone ?? '');
  late final _title = TextEditingController(text: widget.account?.title ?? '');
  final _password = TextEditingController();

  late String _role = widget.account?.role ?? widget.fixedRole ?? 'specialist';
  late String? _specialty = widget.account?.specialty;
  late bool _active = widget.account?.isActive ?? true;

  bool _busy = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  bool get _editing => widget.account != null;

  @override
  void dispose() {
    for (final controller in [_name, _email, _phone, _title, _password]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim();

    if (name.isEmpty || email.isEmpty) {
      setState(() => _error = 'الاسم والبريد مطلوبين.');
      return;
    }

    // The server refuses a specialist without a specialty, and says so — but
    // saying it here saves a round trip on the most common mistake.
    if (_role == 'specialist' && _specialty == null) {
      setState(() => _error = 'الأخصائية لازمها تخصص.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _fieldErrors = const {};
    });

    final body = <String, Object?>{
      'name': name,
      'email': email,
      'role': _role,
      'phone': nullIfEmpty(_phone),
      'title': nullIfEmpty(_title),
      // Sent as null for anything that is not a specialist: a receptionist
      // carrying «النطق واللغة» would show up in the assign picker.
      'specialty': _role == 'specialist' ? _specialty : null,
      if (_editing) 'is_active': _active,
      if (!_editing && _password.text.trim().isNotEmpty) 'password': _password.text.trim(),
    };

    try {
      final api = ref.read(apiProvider);
      // Only a create can hand back a password, so only a create needs the
      // envelope; an edit reads the record straight out of `data`.
      final Account saved;
      String? generated;

      if (_editing) {
        final data = await api.put('/staff/${widget.account!.id}', body: body);
        saved = Account.fromJson(J.map(data) ?? const {});
      } else {
        final response = await api.postEnvelope('/staff', body: body);
        saved = Account.fromJson(J.map(response['data']) ?? const {});
        generated = J.str(J.map(response['meta'])?['generated_password']);
      }

      if (!mounted) return;
      Navigator.of(context).pop(saved);

      if (generated != null) {
        await showPasswordOnce(context, name: saved.name, password: generated);
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
        _fieldErrors = error.errors;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.fixedRole != null;

    return FormSheet(
      title: _editing ? 'تعديل ${widget.account!.name}' : _titleFor(_role),
      subtitle: _editing ? widget.account!.email : null,
      submitLabel: _editing ? 'احفظ' : 'افتح الحساب',
      busy: _busy,
      error: _error,
      onSubmit: _submit,
      children: [
        AppTextField(
          controller: _name,
          label: 'الاسم',
          required: true,
          error: _fieldErrors['name'],
        ),
        AppTextField(
          controller: _email,
          label: 'البريد',
          help: 'فيه بيسجّل الدخول.',
          required: true,
          ltr: true,
          keyboardType: TextInputType.emailAddress,
          error: _fieldErrors['email'],
        ),
        if (!locked)
          ChoiceRow<String>(
            label: 'الدور',
            required: true,
            selected: _role,
            options: const [
              ('specialist', 'أخصائية'),
              ('admin', 'الإدارة'),
              ('guardian', 'ولي أمر'),
            ],
            onSelected: (value) => setState(() {
              _role = value;
              if (value != 'specialist') _specialty = null;
            }),
          ),
        if (_role == 'specialist')
          ChoiceRow<String>(
            label: 'التخصص',
            required: true,
            selected: _specialty,
            options: [for (final e in Labels.specialty.entries) (e.key, e.value)],
            onSelected: (value) => setState(() => _specialty = value),
          ),
        AppTextField(
          controller: _phone,
          label: 'الجوال',
          ltr: true,
          keyboardType: TextInputType.phone,
          error: _fieldErrors['phone'],
        ),
        AppTextField(
          controller: _title,
          label: 'المسمّى الوظيفي',
          help: 'بيظهر تحت الاسم — «أخصائية نطق ولغة».',
          error: _fieldErrors['title'],
        ),
        if (!_editing)
          AppTextField(
            controller: _password,
            label: 'كلمة المرور',
            help: 'اتركها فاضية وبيتولّد وحدة وبتنعرض مرّة وحدة.',
            ltr: true,
            error: _fieldErrors['password'],
          ),
        if (_editing)
          SwitchListTile(
            value: _active,
            onChanged: (value) => setState(() => _active = value),
            contentPadding: EdgeInsets.zero,
            title: const Text('الحساب فعّال'),
            // Switching off is the honest alternative to deleting: her name
            // stays signed on reports families have already read.
            subtitle: const Text('الخامل ما بيقدر يسجّل دخول، بس اسمه بيضلّ على تقاريره.'),
          ),
      ],
    );
  }

  static String _titleFor(String role) => switch (role) {
        'guardian' => 'حساب ولي أمر جديد',
        'admin' => 'حساب إدارة جديد',
        _ => 'أخصائية جديدة',
      };
}

/// A password the server generated, shown once.
///
/// A dialog rather than a toast: it is handed over on a slip of paper, and a
/// message that vanishes in four seconds is a message the office photographs
/// instead of writes down.
Future<void> showPasswordOnce(
  BuildContext context, {
  required String name,
  required String password,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('كلمة المرور'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('حساب $name انفتح. كلمة المرور:'),
          const SizedBox(height: 12),
          SelectableText(
            password,
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'اكتبها الآن — ما بتنعرض مرّة تانية. بتقدر تولّد غيرها من الحساب.',
            style: TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('كتبتها'),
        ),
      ],
    ),
  );
}

/// Generating a new password for an existing account.
Future<void> resetPassword(BuildContext context, WidgetRef ref, Account account) async {
  final sure = await confirm(
    context,
    title: 'ولّد كلمة مرور جديدة لـ${account.name}؟',
    body: 'كلمة المرور القديمة بتبطل فوراً، وبتنعرض الجديدة مرّة وحدة.',
    confirmLabel: 'ولّد',
  );
  if (!sure) return;

  try {
    final response = await ref.read(apiProvider).postEnvelope('/staff/${account.id}/password');
    final password = J.str(J.map(response['meta'])?['generated_password']);

    if (!context.mounted) return;

    if (password == null || password.isEmpty) {
      showToast(context, 'انولّدت كلمة مرور جديدة.');
      return;
    }

    await showPasswordOnce(context, name: account.name, password: password);
  } on ApiException catch (error) {
    if (context.mounted) showFailure(context, error);
  }
}
