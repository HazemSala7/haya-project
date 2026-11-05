import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_exception.dart';
import '../core/auth/session.dart';
import '../core/motion.dart';
import '../core/theme.dart';

/// The door.
///
/// The one screen every person in the academy meets before anything else, so
/// it is built like a front door and not like a form: the academy's own teal
/// across the top with the mark sitting in it, and the two boxes on a white
/// card lifted over the edge of that band. The card arrives a beat after the
/// band, which is what makes it read as a door opening rather than a page
/// loading.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  var _busy = false;
  var _hidden = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'الرجاء ملء جميع الحقول.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(sessionProvider.notifier).signIn(email, password);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'خطأ غير متوقّع.';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          // Room for the keyboard: the card must be able to scroll up over
          // the band rather than be covered by it.
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            // The footer sits at the bottom of a short screen and below the
            // card on a long one. A `Spacer` inside a scroll view needs a
            // bounded height, and this is what bounds it.
            child: IntrinsicHeight(
              child: Column(
              children: [
                const _Banner(),
                Transform.translate(
                  offset: const Offset(0, -34),
                  child: Reveal(
                    delay: const Duration(milliseconds: 140),
                    from: const Offset(0, 0.14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
                        decoration: const BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: AppShape.card,
                          boxShadow: AppShape.cardShadow,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('تسجيل الدخول', style: text.titleLarge),
                            const SizedBox(height: 2),
                            Text('ادخل بالحساب الي أعطتك ياه الأكاديمية.', style: text.bodySmall),
                            const SizedBox(height: 16),

                            // The refusal grows the card rather than appearing
                            // on top of it, so nothing under the thumb moves
                            // the instant it is pressed.
                            AnimatedSize(
                              duration: Motion.medium,
                              curve: Motion.enter,
                              alignment: Alignment.topCenter,
                              child: _error == null ? const SizedBox(width: double.infinity) : _Refusal(_error!),
                            ),

                            TextField(
                              controller: _emailController,
                              enabled: !_busy,
                              /*
                               * Either, and the number in any shape.
                               *
                               * This promise was a lie for a while: the field
                               * offered «أو رقم الهاتف» while AuthController
                               * validated a strict email, so a specialist who
                               * typed the number she had been given was told
                               * her address was invalid. The server takes both
                               * now — see AuthController::byPhone — and a
                               * keypad is a much better place to type ten
                               * digits than an address.
                               */
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                hintText: 'رقم الهاتف أو البريد الإلكتروني',
                                prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                              ),
                              style: text.bodyLarge,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _passwordController,
                              enabled: !_busy,
                              obscureText: _hidden,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _busy ? null : _signIn(),
                              decoration: InputDecoration(
                                hintText: 'كلمة المرور',
                                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                                // Typing a password on a phone keyboard in the
                                // dark is how people get locked out of their
                                // own account.
                                suffixIcon: IconButton(
                                  tooltip: _hidden ? 'إظهار' : 'إخفاء',
                                  onPressed: () => setState(() => _hidden = !_hidden),
                                  icon: Icon(
                                    _hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                    size: 20,
                                  ),
                                ),
                              ),
                              style: text.bodyLarge,
                            ),
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: _busy ? null : _signIn,
                              child: AnimatedSwitcher(
                                duration: Motion.fast,
                                child: _busy
                                    ? const SizedBox(
                                        key: ValueKey(true),
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                                      )
                                    : const Text('دخول', key: ValueKey(false)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'نسيت كلمة المرور؟ إدارة الأكاديمية بتعطيك وحدة جديدة.',
                    textAlign: TextAlign.center,
                    style: text.bodySmall,
                  ),
                ),
                const Spacer(),
                /*
                 * The demo credentials that used to sit here are gone.
                 *
                 * They were three live accounts on the production server
                 * printed in plain sight, one of them an administrator who can
                 * read every child in the academy. A sign-in screen is the one
                 * place in the app that strangers reach, and this one was
                 * handing them the keys.
                 *
                 * They belong in the project's own notes, where the people who
                 * need them already look.
                 */
                Padding(
                  padding: const EdgeInsets.only(top: 20, bottom: 26),
                  child: Text('أكاديمية الحياة · نيوركس', style: text.labelSmall),
                ),
              ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The teal band, with the mark breathing in it.
class _Banner extends StatelessWidget {
  const _Banner();

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;

    // White clock and battery over the teal; the dark set the rest of the app
    // asks for is unreadable on it.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(20, top + 44, 20, 54),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [AppColors.brand, AppColors.brandDeep],
          ),
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(34),
            bottomRight: Radius.circular(34),
          ),
        ),
        child: Column(
          children: [
            Reveal(
              duration: Motion.slow,
              scale: 0.84,
              from: Offset.zero,
              child: Container(
                width: 112,
                height: 112,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 1.4),
                ),
                child: Image.asset('assets/brand/mark.png', fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 18),
            Reveal(
              delay: const Duration(milliseconds: 90),
              child: Column(
                children: [
                  const Text(
                    'أكاديمية الحياة',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.3,
                    ),
                  ),
                  Text(
                    'نظام متابعة التأهيل',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the server said, in red, above the boxes it is about.
class _Refusal extends StatelessWidget {
  const _Refusal(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: AppColors.badSoft, borderRadius: AppShape.control),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.bad),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.bad,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
