import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import 'office_data.dart';

/// The academy's own details.
///
/// Short on purpose: the server validates exactly five keys and ignores the
/// rest, so offering more boxes would be offering boxes that silently do
/// nothing. `report_footer` is the one that matters most — it prints under
/// every report a family reads.
class OfficeSettingsScreen extends ConsumerStatefulWidget {
  const OfficeSettingsScreen({super.key});

  @override
  ConsumerState<OfficeSettingsScreen> createState() => _OfficeSettingsScreenState();
}

class _OfficeSettingsScreenState extends ConsumerState<OfficeSettingsScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _email = TextEditingController();
  final _footer = TextEditingController();

  bool _filled = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in [_name, _phone, _address, _email, _footer]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Filled once from the server. Re-filling on every rebuild would wipe what
  /// is being typed the moment the provider refreshes.
  void _fill(Map<String, String> settings) {
    if (_filled) return;
    _filled = true;

    _name.text = settings['academy_name'] ?? '';
    _phone.text = settings['phone'] ?? '';
    _address.text = settings['address'] ?? '';
    _email.text = settings['email'] ?? '';
    _footer.text = settings['report_footer'] ?? '';
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(apiProvider).put('/settings', body: {
        'academy_name': nullIfEmpty(_name),
        'phone': nullIfEmpty(_phone),
        'address': nullIfEmpty(_address),
        'email': nullIfEmpty(_email),
        'report_footer': nullIfEmpty(_footer),
      });

      if (!mounted) return;
      ref.invalidate(settingsProvider);
      showToast(context, 'انحفظت الإعدادات.');
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات الأكاديمية')),
      body: AsyncView<Map<String, String>>(
        value: settings,
        onRetry: () => reload(ref, settingsProvider.future),
        data: (data) {
          _fill(data);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              AppTextField(controller: _name, label: 'اسم الأكاديمية'),
              const SizedBox(height: 14),
              AppTextField(controller: _phone, label: 'الهاتف', ltr: true),
              const SizedBox(height: 14),
              AppTextField(controller: _email, label: 'البريد', ltr: true),
              const SizedBox(height: 14),
              AppTextField(controller: _address, label: 'العنوان', maxLines: 2),
              const SizedBox(height: 14),
              AppTextField(
                controller: _footer,
                label: 'تذييل التقارير',
                help: 'بينطبع تحت كل تقرير بيقرأه الأهل.',
                maxLines: 4,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(fontFamily: 'Cairo', color: AppColors.bad),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                      )
                    : const Text('احفظ'),
              ),
            ],
          );
        },
      ),
    );
  }
}
