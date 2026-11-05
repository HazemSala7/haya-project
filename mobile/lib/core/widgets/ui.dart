import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_exception.dart';
import '../format.dart';
import '../motion.dart';
import '../theme.dart';

/// A white panel on the tinted canvas. Defined once so thirty call sites
/// cannot drift into thirty slightly different cards.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.onLongPress,
    this.margin,
    this.color,
    this.border,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    final tappable = onTap != null || onLongPress != null;

    Widget body = Container(
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: AppShape.card,
        boxShadow: AppShape.cardShadow,
        border: border,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppShape.card,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );

    // A card that does something gives under the thumb. The ripple alone is
    // under the finger that caused it and tells the person nothing.
    if (tappable) body = Pressable(onTap: onTap, onLongPress: onLongPress, child: body);

    return margin == null ? body : Padding(padding: margin!, child: body);
  }
}

/// A card with a titled head and a hairline under it — the web's `Card title=`.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.hint,
    this.icon,
    this.action,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 16),
  });

  final String title;
  final String? hint;
  final IconData? icon;
  final Widget? action;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 19, color: AppColors.brand),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: text.titleMedium),
                      if (hint != null) Text(hint!, style: text.bodySmall),
                    ],
                  ),
                ),
                ?action,
              ],
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// The small rounded label a status is drawn as.
class ToneChip extends StatelessWidget {
  const ToneChip(this.label, {super.key, this.tone, this.icon, this.solid = false});

  final String label;
  final String? tone;
  final IconData? icon;

  /// Filled with the tone rather than its soft wash — for the one count on a
  /// screen that is waiting for a person.
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.byName(tone);
    final fg = solid ? Colors.white : color;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: icon == null ? 9 : 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: solid ? color : AppColors.softByName(tone),
        borderRadius: AppShape.chip,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: fg,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

/// A level on the prompt scale, in its own colour, with its words.
class LevelChip extends StatelessWidget {
  const LevelChip(this.level, {super.key, this.compact = false});

  final int? level;

  /// Just the number — for rows where the words would wrap.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final value = level;
    if (value == null) {
      return const ToneChip('ما انقاس', tone: 'muted');
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: BoxDecoration(color: LevelColors.fill(value), borderRadius: AppShape.chip),
      child: Text(
        compact ? '$value' : '$value · ${Labels.level(value)}',
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: LevelColors.ink(value),
          height: 1.45,
        ),
      ),
    );
  }
}

/// A specialty's colour dot and name.
class SpecialtyTag extends StatelessWidget {
  const SpecialtyTag(this.specialty, {super.key, this.full = false});

  final String? specialty;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final label = (full ? Labels.specialtyFull : Labels.specialty)[specialty] ?? '—';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: SpecialtyColors.of(specialty), shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ],
    );
  }
}

/// Coloured square behind an icon.
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.tone = 'brand', this.size = 40});

  final IconData icon;
  final String? tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.softByName(tone),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, size: size * 0.52, color: AppColors.byName(tone)),
    );
  }
}

/// Initials on a disc in the logo's colours. Seeded by id, so the same child
/// is the same colour on every screen — which is what makes it read as
/// identity rather than decoration.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, required this.seed, this.size = 44});

  final String name;
  final int seed;
  final double size;

  static const _palette = [
    (Color(0xFFEAF4F3), Color(0xFF1B6A66)),
    (Color(0xFFEEF5F8), Color(0xFF2E6F86)),
    (Color(0xFFF3F6EC), Color(0xFF5F6E3F)),
    (Color(0xFFFDF5E4), Color(0xFF94650A)),
    (Color(0xFFF7EDF4), Color(0xFF94396F)),
  ];

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _palette[seed.abs() % _palette.length];
    // Drop the "أم يوسف —" a guardian's account name often starts with.
    final clean = name.contains('—') ? name.split('—').last : name;
    final parts = clean.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();

    // First name and family name. The middle names in an Arabic full name are
    // the father's and grandfather's, and three initials tell you nothing.
    final initials = parts.isEmpty
        ? '—'
        : parts.length == 1
            ? parts.first.characters.first
            : '${parts.first.characters.first} ${parts.last.characters.first}';

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(
        initials,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: size * 0.32,
          fontWeight: FontWeight.w800,
          color: fg,
          height: 1,
        ),
      ),
    );
  }
}

/// The red band. Allergies, medication, seizures — everything a specialist must
/// know before she is alone in a room with this child. Drawn above every
/// screen that shows the child, not inside a notes tab opened once at intake.
class MedicalAlert extends StatelessWidget {
  const MedicalAlert(this.text, {super.key});

  final String? text;

  @override
  Widget build(BuildContext context) {
    final value = text?.trim();
    if (value == null || value.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.badSoft,
        borderRadius: AppShape.control,
        border: Border.all(color: AppColors.bad.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.medical_information_rounded, color: AppColors.bad, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'تنبيه طبي',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w800,
                    color: AppColors.bad,
                    fontSize: 13,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    color: Color(0xFF7A1F1F),
                    fontSize: 13.5,
                    height: 1.55,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AppLoading extends StatelessWidget {
  const AppLoading({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4)),
            if (label != null) ...[
              const SizedBox(height: 14),
              Text(label!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

/// A failed load. Losing signal is a normal state of a phone, not an alarm —
/// the retry button is the whole message. Anything else says what went wrong,
/// in the server's own sentence.
class AppError extends StatelessWidget {
  const AppError({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final api = error is ApiException ? error as ApiException : null;
    final offline = api?.isConnection ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTile(
              offline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
              tone: offline ? 'warn' : 'bad',
              size: 52,
            ),
            const SizedBox(height: 14),
            Text(
              api?.message ?? 'صار خطأ غير متوقّع.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('جرّب كمان مرة'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(170, 44)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AppEmpty extends StatelessWidget {
  const AppEmpty({super.key, required this.title, this.icon = Icons.inbox_rounded, this.hint, this.action});

  final IconData icon;
  final String title;
  final String? hint;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTile(icon, tone: 'brand', size: 52),
            const SizedBox(height: 14),
            Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(hint!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}


/// Who is signed in, at the top of their own account page.
///
/// A disc with their initials, their name, and what the academy calls them —
/// so the page opens with a person on it rather than with a form of three
/// grey rows.
class AccountHeader extends StatelessWidget {
  const AccountHeader({super.key, required this.name, this.subtitle, this.seed = 0});

  final String name;
  final String? subtitle;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Reveal(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        child: Column(
          children: [
            Avatar(name: name, seed: seed, size: 84),
            const SizedBox(height: 10),
            Text(name, style: text.headlineSmall, textAlign: TextAlign.center),
            if (subtitle != null && subtitle!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: ToneChip(subtitle!, tone: 'brand'),
              ),
          ],
        ),
      ),
    );
  }
}
/// A label and its value, the way every detail block lays one out.
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, required this.value, this.ltr = false});

  final String label;
  final String? value;

  /// Phone numbers, file numbers, emails. Without this the bidi algorithm
  /// reorders a phone number around the Arabic next to it.
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    final text = (value == null || value!.trim().isEmpty) ? '—' : value!;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 104, child: Text(label, style: Theme.of(context).textTheme.labelMedium)),
          Expanded(
            child: Text(
              text,
              textDirection: ltr ? TextDirection.ltr : null,
              textAlign: TextAlign.start,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// One headline number with its caption.
/// One figure, with the word for it.
///
/// The figure rolls up to its value when the tile arrives, and the tile is
/// washed with a breath of its own tone — enough that a row of them reads as
/// a set of different things rather than as five white boxes.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.tone = 'brand',
    this.icon,
    this.onTap,
    this.suffix = '',
  });

  final String label;
  final String value;
  final String? caption;
  final String tone;
  final IconData? icon;
  final VoidCallback? onTap;

  /// «٪» on a rate, a unit on a total.
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colour = AppColors.byName(tone);
    final figure = text.headlineSmall?.copyWith(color: colour == AppColors.muted ? AppColors.ink : colour, height: 1.25);

    // «—» and «٨» are different things: one is a number to roll, the other is
    // the absence of one, and a count-up of nothing is a lie.
    final number = num.tryParse(value);

    return AppCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: AppShape.card,
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [AppColors.softByName(tone).withValues(alpha: 0.55), AppColors.surface],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[IconTile(icon!, tone: tone, size: 32), const SizedBox(width: 8)],
                Expanded(
                  child: Text(label, style: text.labelMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                if (onTap != null) Icon(Icons.chevron_left_rounded, size: 18, color: AppColors.faint),
              ],
            ),
            const SizedBox(height: 8),
            if (number == null)
              Text('$value$suffix', style: figure)
            else
              CountUp(number, suffix: suffix, style: figure),
            if (caption != null) Text(caption!, style: text.labelSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

/// Two stat tiles to a row, whatever the count.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: children[i]),
              const SizedBox(width: 10),
              Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox()),
            ],
          ),
        ),
      );
      if (i + 2 < children.length) rows.add(const SizedBox(height: 10));
    }
    return Column(children: rows);
  }
}

/// A heading between cards.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action, this.count});

  final String title;
  final Widget? action;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Row(
        children: [
          // A short brand bar before the words: the eye finds where a section
          // starts without the heading having to shout in bigger type.
          Container(
            width: 3,
            height: 15,
            margin: const EdgeInsetsDirectional.only(end: 8),
            decoration: const BoxDecoration(color: AppColors.brand, borderRadius: AppShape.chip),
          ),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (count != null) ...[
            const SizedBox(width: 6),
            ToneChip(Fmt.number(count), tone: 'muted'),
          ],
          const Spacer(),
          ?action,
        ],
      ),
    );
  }
}

/// A red count on an icon — the nav bar's "something is waiting".
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    return Badge(
      label: Text(count > 99 ? '99+' : '$count', style: const TextStyle(fontFamily: 'Cairo', fontSize: 10.5)),
      backgroundColor: AppColors.bad,
      child: child,
    );
  }
}

/// Renders an [AsyncValue] the same way everywhere: spinner, error with retry,
/// or the data. Pull-to-refresh is the caller's; this only draws the state.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.data, this.onRetry});

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    // A refresh keeps showing what was there. Swapping a whole screen for a
    // spinner every time somebody pulls down is how a list "flickers".
    if (value.hasValue && !value.hasError) return data(value.requireValue);

    return value.when(
      data: data,
      loading: () => const AppLoading(),
      error: (error, _) => AppError(error: error, onRetry: onRetry),
    );
  }
}

/// A scrolling page body that can be pulled to refresh, even when short.
class RefreshList extends StatelessWidget {
  const RefreshList({
    super.key,
    required this.onRefresh,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 32),
    this.controller,
  });

  final Future<void> Function() onRefresh;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.brand,
      child: ListView(
        controller: controller,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        children: children,
      ),
    );
  }
}

/// Tell the person something happened, in the app's own voice.
void showToast(BuildContext context, String message, {bool bad = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: bad ? AppColors.bad : AppColors.brandDeep,
        content: Row(
          children: [
            Icon(
              bad ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              size: 19,
              color: Colors.white,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        duration: Duration(seconds: bad ? 5 : 3),
      ),
    );
}

/// The failure from a write, as a toast. Keeps the server's sentence.
void showFailure(BuildContext context, Object error) {
  showToast(context, error is ApiException ? error.message : 'صار خطأ غير متوقّع.', bad: true);
}

/// "Are you sure?" — with the consequence written out, not just the verb.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = 'تأكيد',
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(foregroundColor: AppColors.muted),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            minimumSize: const Size(96, 42),
            backgroundColor: danger ? AppColors.bad : AppColors.brand,
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}


/* ------------------------------------------------------- row control */

/// One thing a person may do to one record.
class SheetAction {
  const SheetAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.tone = 'brand',
    this.hint,
    this.disabledReason,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  /// `bad` for anything that destroys; the rest are the palette's words.
  final String tone;

  /// A line under the label — what it will actually do.
  final String? hint;

  /// Shown switched off with the reason under it, rather than hidden. A
  /// missing button leaves the person guessing; «عليها دفعات — احذفها أول»
  /// tells them what to do next.
  final String? disabledReason;
}

/// Everything that can be done to one record, on one sheet.
///
/// The same sheet for a child, a session, an invoice and an account, opened
/// the same way from every list: the ⋮ on the row, or a long press on it. A
/// person who has learnt it once has learnt the whole app.
Future<void> showActions(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<SheetAction> actions,
}) {
  return showModalBottomSheet<void>(
    context: context,
    // Nine actions on a supplier-sized record would otherwise have their
    // last two — the dangerous ones — below the bottom of the screen.
    isScrollControlled: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(sheet).textTheme.titleMedium),
                  if (subtitle != null && subtitle.isNotEmpty)
                    Text(subtitle, style: Theme.of(sheet).textTheme.bodySmall),
                ],
              ),
            ),
            for (final (i, action) in actions.indexed)
              Reveal.at(
                i,
                child: ListTile(
                  enabled: action.disabledReason == null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                  leading: IconTile(
                    action.icon,
                    tone: action.disabledReason == null ? action.tone : 'muted',
                    size: 38,
                  ),
                  title: Text(
                    action.label,
                    style: Theme.of(sheet).textTheme.titleSmall?.copyWith(
                          color: action.disabledReason != null
                              ? AppColors.faint
                              : action.tone == 'bad'
                                  ? AppColors.bad
                                  : AppColors.ink,
                        ),
                  ),
                  subtitle: action.disabledReason != null
                      ? Text(action.disabledReason!, style: Theme.of(sheet).textTheme.bodySmall)
                      : action.hint != null
                          ? Text(action.hint!, style: Theme.of(sheet).textTheme.bodySmall)
                          : null,
                  onTap: () {
                    Navigator.of(sheet).pop();
                    action.onTap();
                  },
                ),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    ),
  );
}

/// The ⋮ at the end of a row.
///
/// Every list in this app puts one here, so «عدّل» and «احذف» are two taps
/// from the row itself rather than behind opening the record first.
class RowMenu extends StatelessWidget {
  const RowMenu({super.key, required this.onTap, this.tooltip = 'تحكّم بالسجل'});

  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppColors.muted),
    );
  }
}
/// A small note in a tinted box — "لسه ما وصل الأهل", "ناقص قبل الإرسال".
class NoteBox extends StatelessWidget {
  const NoteBox(this.text, {super.key, this.tone = 'brand', this.icon});

  final String text;
  final String tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: AppColors.softByName(tone), borderRadius: AppShape.control),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? Icons.info_outline_rounded, size: 18, color: AppColors.byName(tone)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12.5,
                height: 1.55,
                fontWeight: FontWeight.w600,
                color: AppColors.byName(tone),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pull-to-refresh for a provider: re-run it and wait, swallowing the error —
/// the screen draws that itself from the provider's state.
Future<void> reload<T>(WidgetRef ref, Refreshable<Future<T>> future) async {
  try {
    // ignore: unused_result
    await ref.refresh(future);
  } catch (_) {
    // Drawn by the screen.
  }
}

/* ==========================================================================
 * The top of a home screen.
 * ========================================================================== */

/// The greeting band every role opens on.
///
/// It exists because the first screen was two counters reading «٠ | ٠», which
/// is what a broken app looks like and what a quiet day also looks like — and
/// the reader cannot tell which. A person's name, the day's date and one
/// sentence about the day say "this is working, and here is where you are"
/// before any figure is read.
///
/// The wash is the wordmark's teal over its own deeper shade, the same pair
/// the dashboard uses behind its hero, and the corner is cut only at the
/// bottom so the band reads as the top of the page rather than a card
/// floating on it.
class HomeHero extends StatelessWidget {
  const HomeHero({
    super.key,
    required this.name,
    this.subtitle,
    this.line,
    this.trailing,
  });

  final String name;

  /// Her role, under her name — «أخصائية نطق ولغة».
  final String? subtitle;

  /// One sentence about today, in place of a figure.
  final String? line;

  final Widget? trailing;

  /// Arabic greets by the half of the day, not by the hour.
  static String greetingFor(DateTime now) =>
      now.hour < 12 ? 'صباح الخير' : now.hour < 17 ? 'نهارك سعيد' : 'مساء الخير';

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final text = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 18, 20, 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [AppColors.brand, AppColors.brandDeep],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      greetingFor(now),
                      style: text.bodyMedium?.copyWith(color: Colors.white70),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name,
                      style: text.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        style: text.bodySmall?.copyWith(color: Colors.white70),
                      ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              const Icon(Icons.calendar_today_rounded, size: 14, color: Colors.white70),
              const SizedBox(width: 6),
              Text(
                Fmt.dayDate(Fmt.isoDate(now)),
                style: text.bodySmall?.copyWith(color: Colors.white70),
              ),
            ],
          ),

          if (line != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: AppShape.control,
              ),
              child: Text(
                line!,
                style: text.bodyMedium?.copyWith(color: Colors.white, height: 1.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}


/// A page whose top is the teal hero band.
///
/// The clock and the battery live over that band, and the dark set the rest
/// of the app asks for is nearly invisible on teal — so this flips them to
/// white while the band is under them and back to dark once it has been
/// scrolled away. Wrapping the scrollable rather than the band is the point:
/// an annotation on the band itself keeps claiming the bar long after the
/// band has gone off the top of the screen.
class HeroPage extends StatefulWidget {
  const HeroPage({super.key, required this.child, this.threshold = 90});

  final Widget child;

  /// How far the page scrolls before the bar is no longer over the band.
  final double threshold;

  @override
  State<HeroPage> createState() => _HeroPageState();
}

class _HeroPageState extends State<HeroPage> {
  var _onBand = true;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      sized: false,
      value: (_onBand ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(statusBarColor: Colors.transparent),
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: (note) {
          // Only the page's own scroll: a horizontal strip of chips inside it
          // must not decide what colour the clock is.
          if (note.metrics.axis != Axis.vertical) return false;
          final onBand = note.metrics.pixels < widget.threshold;
          if (onBand != _onBand) setState(() => _onBand = onBand);
          return false;
        },
        child: Stack(
          children: [
            widget.child,
            // Once the band is gone, the rows underneath would otherwise run
            // up behind the clock. A wash the colour of the page, fading in
            // exactly when the band leaves, gives them an edge to pass under.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _onBand ? 0 : 1,
                  duration: Motion.medium,
                  curve: Motion.enter,
                  child: Container(
                    height: MediaQuery.paddingOf(context).top,
                    color: AppColors.canvas.withValues(alpha: 0.94),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
/// A single figure on the hero's own colour.
class HeroFigure extends StatelessWidget {
  const HeroFigure({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: text.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        Text(label, style: text.labelSmall?.copyWith(color: Colors.white70)),
      ],
    );
  }
}

/// The one thing on the screen that is asking to be done.
///
/// Warm rather than red: unwritten reports are a backlog, not an emergency,
/// and the only red in this app belongs to the medical band. It carries its
/// own age because a count alone cannot tell a busy afternoon apart from a
/// report a family has been waiting three weeks for.
class ActionBanner extends StatelessWidget {
  const ActionBanner({
    super.key,
    required this.title,
    required this.body,
    required this.icon,
    this.tone = 'warn',
    this.onTap,
    this.actionLabel,
  });

  final String title;
  final String body;
  final IconData icon;
  final String tone;
  final VoidCallback? onTap;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colour = AppColors.byName(tone);

    return AppCard(
      onTap: onTap,
      color: AppColors.softByName(tone),
      border: Border.all(color: colour.withValues(alpha: 0.28)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(icon, tone: tone),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.titleSmall?.copyWith(color: colour, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(body, style: text.bodySmall?.copyWith(height: 1.5)),
                if (actionLabel != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        actionLabel!,
                        style: text.labelLarge?.copyWith(color: colour),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_back_rounded, size: 15, color: colour),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
