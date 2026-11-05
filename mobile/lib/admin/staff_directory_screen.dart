import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import 'office_data.dart';
import 'staff_form.dart';

/// Everyone with a login — and what the office may do to each account.
///
/// This screen used to list the specialists and stop there: no tap, no edit,
/// no way to open an account or close one. It also used `specialistsProvider`,
/// which filters `role=specialist` because it exists to fill the "assign a
/// programme to" picker — so the second admin and every parent account were
/// invisible. An account nobody can see is an account that keeps working.
class StaffDirectoryScreen extends ConsumerStatefulWidget {
  const StaffDirectoryScreen({super.key});

  @override
  ConsumerState<StaffDirectoryScreen> createState() => _StaffDirectoryScreenState();
}

class _StaffDirectoryScreenState extends ConsumerState<StaffDirectoryScreen> {
  final _search = TextEditingController();

  String _role = 'specialist';
  String _query = '';
  bool? _active;
  Timer? _debounce;

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

  ({String role, String search, bool? active}) get _filter =>
      (role: _role, search: _query, active: _active);

  Future<void> _refresh() => reload(ref, staffProvider(_filter).future);

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(staffProvider(_filter));

    return Scaffold(
      appBar: AppBar(title: const Text('الفريق'), centerTitle: false),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await openStaffForm(context, ref);
          if (created == null || !context.mounted) return;
          showToast(context, 'انفتح حساب ${created.name}.');
          await _refresh();
        },
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('حساب جديد'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: _search,
                  onChanged: _onTyped,
                  decoration: InputDecoration(
                    hintText: 'ابحث بالاسم أو البريد…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _search.clear();
                              _onTyped('');
                            },
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final (value, label) in const [
                        ('specialist', 'الأخصائيات'),
                        ('admin', 'الإدارة'),
                        ('guardian', 'الأولياء'),
                        ('', 'الكل'),
                      ])
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: ChoiceChip(
                            label: Text(label),
                            selected: _role == value,
                            onSelected: (_) => setState(() => _role = value),
                          ),
                        ),
                      const SizedBox(width: 4),
                      // Inactive accounts are the point of this filter: they
                      // are invisible everywhere else and they can still be
                      // reactivated by mistake.
                      FilterChip(
                        label: const Text('الخاملين فقط'),
                        selected: _active == false,
                        onSelected: (on) => setState(() => _active = on ? false : null),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView<List<Account>>(
              value: accounts,
              onRetry: _refresh,
              data: (list) => list.isEmpty
                  ? AppEmpty(
                      icon: Icons.people_outline,
                      title: _query.isEmpty ? 'ما في حسابات هون' : 'ما لقينا «$_query»',
                      hint: 'بدّل الفلتر، أو افتح حساباً جديداً.',
                    )
                  : RefreshList(
                      onRefresh: _refresh,
                      children: [
                        for (final account in list)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: StaffCard(
                              account: account,
                              onTap: () => _openSheet(account),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSheet(Account account) async {
    await showFormSheet<void>(
      context,
      builder: (_) => _StaffActions(account: account, onDone: _refresh),
    );
  }
}

/// Everything the office may do to one account, on one sheet.
class _StaffActions extends ConsumerWidget {
  const _StaffActions({required this.account, required this.onDone});

  final Account account;
  final Future<void> Function() onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = ref.watch(staffChildrenProvider(account.id));
    final text = Theme.of(context).textTheme;

    Future<void> close() async {
      Navigator.of(context).pop();
      await onDone();
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Avatar(name: account.name, seed: account.id, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(account.name, style: text.titleMedium),
                      Text(
                        account.email,
                        style: text.bodySmall?.copyWith(color: AppColors.muted),
                        textDirection: TextDirection.ltr,
                      ),
                    ],
                  ),
                ),
                ToneChip(
                  account.isActive ? 'نشط' : 'خامل',
                  tone: account.isActive ? 'good' : 'muted',
                  solid: account.isActive,
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Who depends on this account. Shown before the destructive
            // actions rather than after, because "deactivate" means something
            // different when four children are on her caseload.
            children.when(
              loading: () => const AppLoading(),
              error: (_, __) => const SizedBox.shrink(),
              data: (list) => list.isEmpty
                  ? const SizedBox.shrink()
                  : NoteBox(
                      'مسؤولة عن ${Fmt.children(list.length)}: '
                      '${list.take(4).map((s) => s.name).join('، ')}'
                      '${list.length > 4 ? '…' : ''}',
                      tone: 'brand',
                      icon: Icons.people_alt_rounded,
                    ),
            ),

            const SizedBox(height: 4),

            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const IconTile(Icons.edit_outlined),
              title: const Text('عدّل الحساب'),
              subtitle: const Text('الاسم، البريد، الدور، التخصص، التفعيل'),
              onTap: () async {
                final saved = await openStaffForm(context, ref, account: account);
                if (saved == null) return;
                if (context.mounted) await close();
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const IconTile(Icons.key_rounded, tone: 'warn'),
              title: const Text('ولّد كلمة مرور'),
              subtitle: const Text('بتبطل القديمة وبتقفل كل جلساته'),
              onTap: () async {
                await resetPassword(context, ref, account);
                if (context.mounted) await close();
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const IconTile(Icons.delete_outline_rounded, tone: 'bad'),
              title: const Text('احذف الحساب', style: TextStyle(color: AppColors.bad)),
              subtitle: const Text('الأفضل تعطيله — اسمه موقّع على تقارير وصلت الأهل'),
              onTap: () async {
                final sure = await confirm(
                  context,
                  title: 'احذف حساب ${account.name}؟',
                  body: 'الحذف ما بينفع إذا كان موقّعاً على تقارير أو جلسات — '
                      'الخادم بيرفضه وبيقترح التعطيل. التعطيل بيوقف الدخول '
                      'وبيخلّي اسمه على شغله.',
                  confirmLabel: 'احذف',
                  danger: true,
                );
                if (!sure) return;

                try {
                  await ref.read(apiProvider).delete('/staff/${account.id}');
                  if (!context.mounted) return;
                  showToast(context, 'انحذف الحساب.');
                  await close();
                } on ApiException catch (error) {
                  if (context.mounted) showFailure(context, error);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// One account in the list.
class StaffCard extends StatelessWidget {
  const StaffCard({super.key, required this.account, this.onTap});

  final Account account;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return AppCard(
      onTap: onTap,
      onLongPress: onTap,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Avatar(name: account.name, seed: account.id, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(account.name, style: text.titleSmall),
                Text(
                  account.title?.isNotEmpty == true
                      ? account.title!
                      : Labels.role[account.role] ?? account.role,
                  style: text.bodySmall?.copyWith(color: AppColors.muted),
                ),
                if (account.specialty != null && account.specialty!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  SpecialtyTag(account.specialty),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ToneChip(
                account.isActive ? 'نشط' : 'خامل',
                tone: account.isActive ? 'good' : 'muted',
                solid: account.isActive,
              ),
              if ((account.childrenCount ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    Fmt.children(account.childrenCount!),
                    style: text.labelSmall?.copyWith(color: AppColors.muted),
                  ),
                ),
            ],
          ),
          // The whole card already opens the actions, but the ⋮ is what the
          // other lists trained the thumb to look for.
          if (onTap != null) RowMenu(onTap: onTap!),
        ],
      ),
    );
  }
}
