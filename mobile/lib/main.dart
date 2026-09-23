import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth/session.dart' as auth;
import 'core/theme.dart';
import 'core/core.dart' show AppColors, AppRole, Profile;
import 'core/widgets/ui.dart';
import 'shared/login_screen.dart';
import 'admin/admin_shell.dart';
import 'specialist/specialist_shell.dart';
import 'guardian/guardian_shell.dart';

void main() {
  runApp(const ProviderScope(child: HayaApp()));
}

class HayaApp extends StatelessWidget {
  const HayaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'أكاديمية الحياة',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _Root(),
    );
  }
}

/// Picks which product opens based on the role the server returned.
class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(auth.sessionProvider);

    return switch (session.status) {
      auth.SessionStatus.restoring => const _Splash(),
      auth.SessionStatus.signedOut => const LoginScreen(),
      auth.SessionStatus.signedIn => _shellFor(session.user!),
    };
  }

  Widget _shellFor(Profile user) => switch (user.role) {
        AppRole.guardian => const GuardianShell(),
        AppRole.specialist => const SpecialistShell(),
        AppRole.admin => const AdminShell(),
        AppRole.unknown => const _NoShell(),
      };
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.canvas,
      body: Center(
        child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4)),
      ),
    );
  }
}

class _NoShell extends ConsumerWidget {
  const _NoShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: AppEmpty(
          icon: Icons.phonelink_off_rounded,
          title: 'لا توجد شاشة لهذا الحساب',
          hint: 'راجع إدارة الأكاديمية إن كنت تتوقّع غير ذلك.',
          action: OutlinedButton.icon(
            onPressed: () => ref.read(auth.sessionProvider.notifier).signOut(),
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('تسجيل خروج'),
          ),
        ),
      ),
    );
  }
}
