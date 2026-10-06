import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';

/*
 * Closing your own account, from inside the app.
 *
 * Both stores require this of any app that holds accounts, and the shape they
 * want is not a button: a person must be able to see what they are about to
 * lose before they lose it.
 *
 * Every word of that comes from `GET /auth/account` rather than from here. The
 * answer differs by who is asking — a parent's login can go, a specialist whose
 * name is signed on reports families have already read is closed rather than
 * erased — and a second copy of that rule on the client is a copy that will one
 * day disagree with the server about what just happened to somebody's data.
 */
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _password = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _confirm(Map<String, dynamic> preview) async {
    final canDelete = J.boolean(preview['can_delete']);

    final ok = await confirm(
      context,
      title: canDelete ? 'حذف الحساب نهائياً؟' : 'إغلاق الحساب؟',
      body: canDelete
          ? 'ما في تراجع عن هاي الخطوة.'
          : 'رح تطلعي من كل الأجهزة، وما بتقدري تدخلي إلا بعد ما تفتحه الإدارة.',
      confirmLabel: canDelete ? 'احذف' : 'أغلق',
      danger: true,
    );

    if (!ok) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(apiProvider).delete(
            '/auth/account',
            body: {'password': _password.text},
          );

      // Whatever the server did — erased or closed — this device is signed out.
      await ref.read(sessionProvider.notifier).signOut();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = ref.watch(accountPreviewProvider);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('حذف الحساب')),
      body: AsyncView(
        value: preview,
        onRetry: () => reload(ref, accountPreviewProvider.future),
        data: (data) {
          final goes = J.strings(data['what_goes']);
          final stays = J.strings(data['what_stays']);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text(J.s(data['title']), style: text.titleLarge),
              const SizedBox(height: 18),

              _Block(
                title: 'اللي بيروح',
                icon: Icons.remove_circle_outline_rounded,
                tone: 'bad',
                lines: goes,
              ),

              if (stays.isNotEmpty) ...[
                const SizedBox(height: 12),
                _Block(
                  title: 'اللي بيضلّ',
                  icon: Icons.shield_outlined,
                  tone: 'good',
                  lines: stays,
                ),
              ],

              const SizedBox(height: 22),

              AppTextField(
                controller: _password,
                label: 'كلمة المرور',
                help: 'للتأكد إنك إنتِ.',
                obscure: true,
                required: true,
                error: _error,
                enabled: !_busy,
              ),

              const SizedBox(height: 20),

              FilledButton.icon(
                onPressed: _busy || _password.text.isEmpty ? null : () => _confirm(data),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.bad,
                  minimumSize: const Size.fromHeight(52),
                ),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                      )
                    : const Icon(Icons.delete_outline_rounded, size: 19),
                label: Text(J.boolean(data['can_delete']) ? 'احذف حسابي' : 'أغلق حسابي'),
              ),

              const SizedBox(height: 10),
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const Text('تراجع'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({
    required this.title,
    required this.icon,
    required this.tone,
    required this.lines,
  });

  final String title;
  final IconData icon;
  final String tone;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colour = AppColors.byName(tone);

    return AppCard(
      color: AppColors.softByName(tone),
      border: Border.all(color: colour.withValues(alpha: 0.25)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: colour),
              const SizedBox(width: 7),
              Text(title, style: text.titleSmall?.copyWith(color: colour)),
            ],
          ),
          const SizedBox(height: 9),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(line, style: text.bodyMedium?.copyWith(height: 1.8)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
