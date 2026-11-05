import 'dart:async';

import 'package:flutter/material.dart';

import 'format.dart';
import 'theme.dart';

/*
 * How this app moves.
 *
 * One file so the whole product moves at the same speed, the way it is one
 * palette and one type scale. Motion here is not decoration: it says where a
 * thing came from (a card rises into place from just below, so the eye knows
 * it belongs to the list under it), that a press was felt (every tappable
 * surface gives under the thumb), and that a figure is live rather than
 * printed (counts roll up to their value).
 *
 * Everything below is hand-written against the framework's own implicit
 * animations — no animation package — because the app already pins its
 * dependencies tightly and a curve is four lines.
 */

abstract final class Motion {
  /// A press, a chip, a colour change.
  static const fast = Duration(milliseconds: 160);

  /// The common one: a card arriving, a tab fading in.
  static const medium = Duration(milliseconds: 300);

  /// Entrances, so they read as arriving rather than appearing.
  static const slow = Duration(milliseconds: 520);

  /// Numbers counting up — long enough to be seen, short enough that a
  /// person who looked away for a second did not miss it.
  static const count = Duration(milliseconds: 950);

  /// Material's emphasised-decelerate shape: fast out of the gate, long settle.
  static const enter = Cubic(0.05, 0.7, 0.1, 1);
  static const exit = Cubic(0.3, 0, 0.8, 0.15);

  /// A little overshoot — only for things that should feel springy, like the
  /// selected tab's icon. Never for text.
  static const spring = Curves.easeOutBack;

  /// One row after another, for staggered lists. Twelve rows × 40ms is under
  /// half a second for the whole list, which is the budget.
  static const step = Duration(milliseconds: 45);

  /// Beyond this, a stagger stops adding delay: a long list must not make the
  /// twentieth row wait a second to exist.
  static const maxStagger = Duration(milliseconds: 360);
}

/// Fade and lift a widget into place once, when it is first built.
///
/// [delay] is what makes a list arrive as a list rather than a block — pass
/// the row's index through [Reveal.at]. The child is laid out and painted the
/// whole time; only opacity and a small offset animate, so nothing reflows.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = Motion.slow,
    this.from = const Offset(0, 0.08),
    this.scale = 1,
  });

  /// The [index]th thing on the screen, staggered behind the ones before it.
  Reveal.at(int index, {Key? key, required Widget child, Duration? duration, Offset? from})
      : this(
          key: key,
          delay: index <= 0
              ? Duration.zero
              : Duration(
                  milliseconds: (Motion.step.inMilliseconds * index).clamp(0, Motion.maxStagger.inMilliseconds),
                ),
          duration: duration ?? Motion.slow,
          from: from ?? const Offset(0, 0.08),
          child: child,
        );

  final Widget child;
  final Duration delay;
  final Duration duration;

  /// Where it comes from, in fractions of its own size.
  final Offset from;

  /// Start slightly small — for a hero figure or a single card, not for rows.
  final double scale;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> {
  bool _shown = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      // The first frame must still be the "before" state, or there is nothing
      // to animate from.
      WidgetsBinding.instance.addPostFrameCallback((_) => _show());
    } else {
      _timer = Timer(widget.delay, _show);
    }
  }

  void _show() {
    if (mounted) setState(() => _shown = true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: _shown ? Offset.zero : widget.from,
      duration: widget.duration,
      curve: Motion.enter,
      child: AnimatedScale(
        scale: _shown ? 1 : widget.scale,
        duration: widget.duration,
        curve: Motion.enter,
        child: AnimatedOpacity(
          opacity: _shown ? 1 : 0,
          duration: widget.duration,
          curve: Motion.enter,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Wrap each child in a staggered [Reveal], keeping the list's own order.
List<Widget> revealAll(List<Widget> children, {int from = 0}) => [
      for (final (i, child) in children.indexed) Reveal.at(i + from, child: child),
    ];

/// Gives under the thumb.
///
/// Used by every card and tile that does something when pressed, so "this is
/// tappable" is answered by the surface itself instead of by a ripple the
/// finger is covering.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.onLongPress, this.scale = 0.97});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (widget.onTap == null && widget.onLongPress == null) return;
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: Motion.fast,
        curve: Motion.enter,
        child: widget.child,
      ),
    );
  }
}

/// A figure that rolls up to its value.
///
/// It animates from whatever it last showed, so a refresh that changes 8 to 9
/// moves by one rather than counting from zero again.
class CountUp extends StatelessWidget {
  const CountUp(this.value, {super.key, this.style, this.suffix = '', this.duration = Motion.count});

  final num? value;
  final TextStyle? style;

  /// «٪» on a rate, a unit on a total.
  final String suffix;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (value == null) return Text('—$suffix', style: style);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value!.toDouble()),
      duration: duration,
      curve: Motion.enter,
      builder: (context, shown, _) => Text(
        '${Fmt.number(shown.round())}$suffix',
        style: style,
        // A number that grows must not shove its neighbours about mid-roll.
        maxLines: 1,
      ),
    );
  }
}

/// The pale sweep over a placeholder while the real thing loads.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _wave,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: const [AppColors.surfaceMuted, AppColors.lineSoft, AppColors.surfaceMuted],
          stops: const [0.25, 0.5, 0.75],
          transform: _Slide(_wave.value),
        ).createShader(bounds),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// Slides a gradient across the box it paints, once per cycle.
class _Slide extends GradientTransform {
  const _Slide(this.t);

  final double t;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (t * 2 - 1), 0, 0);
}

/// One grey bar standing in for a line of text or a figure.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(radius)),
    );
  }
}

/// The shape of a screen before its data lands.
///
/// A list of grey cards the size of the real ones is a better wait than a
/// spinner in the middle of nothing: the page does not jump when the rows
/// arrive, and the person already knows what is coming.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.rows = 5, this.height = 84, this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 16)});

  final int rows;
  final double height;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Padding(
        padding: padding,
        child: Column(
          children: [
            for (var i = 0; i < rows; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  height: height,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: AppShape.card,
                    boxShadow: AppShape.cardShadow,
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const SkeletonBox(width: 42, height: 42, radius: 21),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SkeletonBox(width: 140 + (i % 3) * 30, height: 13),
                            const SizedBox(height: 8),
                            SkeletonBox(width: 90 + (i % 2) * 40, height: 11),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// How one screen gives way to the next.
///
/// Material's default on Android slides the whole page up from the bottom,
/// which on an RTL phone reads as a sheet rather than a step forward. This is
/// the quieter one every modern app uses: the new page fades in while growing
/// the last two per cent, the old one fades and shrinks a touch behind it.
class FadeThroughTransitions extends PageTransitionsBuilder {
  const FadeThroughTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext? context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final incoming = CurvedAnimation(parent: animation, curve: Motion.enter, reverseCurve: Motion.exit);
    final outgoing = CurvedAnimation(parent: secondaryAnimation, curve: Motion.enter, reverseCurve: Motion.exit);

    return FadeTransition(
      opacity: incoming,
      child: ScaleTransition(
        scale: Tween(begin: 0.97, end: 1.0).animate(incoming),
        child: FadeTransition(
          opacity: Tween(begin: 1.0, end: 0.0).animate(outgoing),
          child: ScaleTransition(
            scale: Tween(begin: 1.0, end: 1.03).animate(outgoing),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Push a screen with the app's own transition, from anywhere.
Future<T?> openScreen<T>(BuildContext context, Widget screen) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => screen));
