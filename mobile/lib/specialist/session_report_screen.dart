import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';

/*
 * Writing up a session.
 *
 * This is the specialist's whole job on the phone, and the screen it replaces
 * could not do it: it posted to `/therapy_sessions/{id}/report`, a path that
 * does not exist in this API, so every report she wrote was lost on save. It
 * also opened blank, which meant a half-written draft could only ever be
 * rewritten from nothing.
 *
 * ---------------------------------------------------------------------------
 * SAVING AND SENDING ARE TWO DIFFERENT ACTS.
 *
 * A draft is hers, and she can save it ten times between two sessions. Sending
 * hands it to a family and freezes it — the server refuses a second publish and
 * tells her to add a line instead. So they are two buttons, and the loud one is
 * the one that is reversible.
 *
 * ---------------------------------------------------------------------------
 * WHAT THE SERVER REFUSES, THIS SCREEN SAYS FIRST.
 *
 * `ReportDesk::publish` will not send a report without «الأنشطة» or «الخطة
 * المنزلية», and will not send one at all until the session is marked held.
 * Those refusals come back as good Arabic sentences, but a rule a person only
 * meets by failing is a rule the screen should have shown — so the two fields
 * are marked required and the attendance state is offered up top.
 */
class SessionReportScreen extends ConsumerStatefulWidget {
  const SessionReportScreen({
    super.key,
    required this.sessionId,
    required this.studentName,
  });

  final int sessionId;
  final String studentName;

  @override
  ConsumerState<SessionReportScreen> createState() => _SessionReportScreenState();
}

class _SessionReportScreenState extends ConsumerState<SessionReportScreen> {
  final _activities = TextEditingController();
  final _progress = TextEditingController();
  final _difficulties = TextEditingController();
  final _homePlan = TextEditingController();
  final _notes = TextEditingController();

  String? _mood;
  var _busy = false;
  var _loaded = false;

  @override
  void dispose() {
    for (final c in [_activities, _progress, _difficulties, _homePlan, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Fill the form from the draft already on the server, once.
  void _fill(TherapySession s) {
    if (_loaded) return;
    _loaded = true;
    _activities.text = s.activities ?? '';
    _progress.text = s.progress ?? '';
    _difficulties.text = s.difficulties ?? '';
    _homePlan.text = s.homePlan ?? '';
    _notes.text = s.privateNotes ?? '';
    _mood = s.mood;
  }

  Map<String, dynamic> get _body => {
        'mood': _mood,
        'activities': nullIfEmpty(_activities),
        'progress': nullIfEmpty(_progress),
        'difficulties': nullIfEmpty(_difficulties),
        'home_plan': nullIfEmpty(_homePlan),
        'private_notes': nullIfEmpty(_notes),
      };

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (error) {
      if (mounted) showToast(context, error.message, bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() => _run(() async {
        await ref.read(apiProvider).put('/sessions/${widget.sessionId}', body: _body);
        _refresh();
        if (mounted) showToast(context, 'انحفظت المسودة.');
      });

  Future<void> _publish() => _run(() async {
        final api = ref.read(apiProvider);
        // Save first: publishing reads what is on the server, not what is on
        // screen, and sending a report that is missing the paragraph she just
        // typed is the one failure she would never forgive.
        await api.put('/sessions/${widget.sessionId}', body: _body);
        await api.post('/sessions/${widget.sessionId}/publish');
        _refresh();
        if (!mounted) return;
        showToast(context, 'انبعت التقرير للأهل.');
        Navigator.of(context).pop(true);
      });

  Future<void> _markHeld() => _run(() async {
        await ref
            .read(apiProvider)
            .post('/sessions/${widget.sessionId}/attendance', body: {'status': 'held'});
        _refresh();
        if (mounted) showToast(context, 'علّمنا الجلسة «تمّت».');
      });

  void _refresh() {
    reload(ref, sessionProvider(widget.sessionId).future);
    reload(ref, dashboardProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider(widget.sessionId));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.studentName, style: Theme.of(context).textTheme.titleMedium),
            Text('تقرير الجلسة', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      body: AsyncView(
        value: session,
        onRetry: () => reload(ref, sessionProvider(widget.sessionId).future),
        data: (s) {
          _fill(s);

          final published = s.reportStatus == 'published';
          final held = s.status == 'held';

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    if (s.student?.medicalAlert != null && s.student!.medicalAlert!.isNotEmpty) ...[
                      MedicalAlert(s.student!.medicalAlert!),
                      const SizedBox(height: 14),
                    ],

                    _Strip(session: s),
                    const SizedBox(height: 14),

                    // A published report is frozen by the server. Saying so
                    // beats letting her type for ten minutes into a refusal.
                    if (published)
                      const NoteBox(
                        'هذا التقرير انبعت للأهل وما بينعدّل. التصحيح بيكون بإضافة سطر عليه.',
                        tone: 'info',
                        icon: Icons.lock_rounded,
                      )
                    else if (!held)
                      ActionBanner(
                        icon: Icons.event_available_rounded,
                        title: 'الجلسة لسّا مش معلّمة «تمّت»',
                        body: 'ما بينبعت تقرير عن جلسة ما تمّت.',
                        actionLabel: 'علّمها تمّت',
                        tone: 'warn',
                        onTap: _busy ? null : _markHeld,
                      ),

                    const SizedBox(height: 16),

                    _MoodPicker(
                      value: _mood,
                      enabled: !published && !_busy,
                      onChanged: (m) => setState(() => _mood = m),
                    ),
                    const SizedBox(height: 16),

                    AppTextField(
                      controller: _activities,
                      label: 'شو عملتوا بالجلسة',
                      hint: 'الأنشطة والتمارين، بالترتيب.',
                      required: true,
                      maxLines: 5,
                      minLines: 3,
                      enabled: !published,
                    ),
                    const SizedBox(height: 14),

                    AppTextField(
                      controller: _progress,
                      label: 'كيف كان معكم',
                      hint: 'شو لاحظتِ — تحسّن، مبادرة، انتباه.',
                      help: 'هاد أول شي بتقرأه الأم.',
                      maxLines: 5,
                      minLines: 3,
                      enabled: !published,
                    ),
                    const SizedBox(height: 14),

                    AppTextField(
                      controller: _difficulties,
                      label: 'شو صعب عليه',
                      hint: 'إن وُجد — وإن ما كان في، اكتبي ذلك.',
                      maxLines: 4,
                      minLines: 2,
                      enabled: !published,
                    ),
                    const SizedBox(height: 14),

                    AppTextField(
                      controller: _homePlan,
                      label: 'شو بدكم من الأهل بالبيت',
                      hint: 'خطوة وحدة واضحة يقدروا يعملوها.',
                      help: 'الجزء الوحيد اللي الأسرة بتقدر تشتغل عليه.',
                      required: true,
                      maxLines: 4,
                      minLines: 2,
                      enabled: !published,
                    ),
                    const SizedBox(height: 18),

                    /*
                     * The private column, fenced.
                     *
                     * `private_notes` is hidden on the model and only made
                     * visible to staff, so a parent cannot read it — but the
                     * person typing has no way to know that unless the screen
                     * says it, and a specialist who is unsure writes nothing.
                     */
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceMuted,
                        borderRadius: AppShape.card,
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.visibility_off_rounded,
                                  size: 16, color: AppColors.muted),
                              const SizedBox(width: 6),
                              Text(
                                'ملاحظات داخلية — الأهل ما بيشوفوها',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          AppTextField(
                            controller: _notes,
                            label: '',
                            hint: 'للفريق والملف، مش للأسرة.',
                            maxLines: 4,
                            minLines: 2,
                            enabled: !published,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              if (!published)
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      border: Border(top: BorderSide(color: AppColors.lineSoft)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _save,
                            icon: const Icon(Icons.save_rounded, size: 18),
                            label: const Text('حفظ مسودة'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: _busy || !held ? null : _confirmPublish,
                            icon: _busy
                                ? const SizedBox(
                                    width: 17,
                                    height: 17,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.2, color: Colors.white),
                                  )
                                : const Icon(Icons.send_rounded, size: 18),
                            label: const Text('إرسال للأهل'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmPublish() async {
    final ok = await confirm(
      context,
      title: 'إرسال التقرير؟',
      body: 'بيوصل أهل ${widget.studentName} فوراً، وما بينعدّل بعدها — '
          'التصحيح بيكون بإضافة سطر عليه.',
      confirmLabel: 'إرسال',
    );

    if (ok) await _publish();
  }
}

/// Which session this is, in one line.
class _Strip extends StatelessWidget {
  const _Strip({required this.session});

  final TherapySession session;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Row(
      children: [
        SpecialtyTag(session.specialty, full: true),
        const Spacer(),
        Text(
          '${Fmt.dayDate(session.scheduledAt)} · ${Fmt.time(session.scheduledAt)}',
          style: text.bodySmall,
        ),
      ],
    );
  }
}

/// The six moods, as faces.
class _MoodPicker extends StatelessWidget {
  const _MoodPicker({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String? value;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('كيف كان مزاجه', style: text.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mood in Labels.moods)
              GestureDetector(
                // Tapping the chosen one again clears it: a mood nobody
                // observed is better left empty than guessed at.
                onTap: enabled ? () => onChanged(value == mood ? null : mood) : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: value == mood ? AppColors.brandSoft : AppColors.surface,
                    borderRadius: AppShape.control,
                    border: Border.all(
                      color: value == mood ? AppColors.brand : AppColors.line,
                      width: value == mood ? 1.6 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(Labels.moodFace[mood] ?? '', style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 6),
                      Text(
                        Labels.mood[mood] ?? mood,
                        style: text.labelMedium?.copyWith(
                          color: value == mood ? AppColors.brandDeep : AppColors.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
