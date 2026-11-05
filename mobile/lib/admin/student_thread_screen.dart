import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';

/// The thread about one child, from the office's side.
///
/// The guardian app has its own messages screen — it opens whichever child the
/// family is looking at. The office needs to open any child's thread from his
/// file, which is a different entry point into the same endpoint, so this is
/// a thin screen rather than a second messaging feature.
class StudentThreadScreen extends ConsumerStatefulWidget {
  const StudentThreadScreen({super.key, required this.student});

  final Student student;

  @override
  ConsumerState<StudentThreadScreen> createState() => _StudentThreadScreenState();
}

class _StudentThreadScreenState extends ConsumerState<StudentThreadScreen> {
  final _draft = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _draft.text.trim();
    if (body.isEmpty) return;

    setState(() => _sending = true);

    try {
      await ref
          .read(apiProvider)
          .post('/students/${widget.student.id}/messages', body: {'body': body});

      _draft.clear();
      if (!mounted) return;
      await reload(ref, threadProvider(widget.student.id).future);
    } on ApiException catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final thread = ref.watch(threadProvider(widget.student.id));
    final me = ref.watch(meProvider);

    return Scaffold(
      appBar: AppBar(title: Text('مراسلات ${widget.student.name}')),
      body: Column(
        children: [
          Expanded(
            child: AsyncView<List<ChatMessage>>(
              value: thread,
              onRetry: () => reload(ref, threadProvider(widget.student.id).future),
              data: (messages) => messages.isEmpty
                  ? const AppEmpty(
                      icon: Icons.forum_outlined,
                      title: 'ما في مراسلات',
                      hint: 'اكتب أول رسالة للأهل من تحت.',
                    )
                  : ListView.builder(
                      // Newest first from the API; the list is reversed so the
                      // newest sits at the bottom where a thread is read.
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        return _Bubble(message: message, mine: message.senderId == me?.id);
                      },
                    ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _draft,
                      minLines: 1,
                      maxLines: 5,
                      decoration: const InputDecoration(hintText: 'اكتب للأهل…'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine});

  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine ? AppColors.softByName('brand') : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.sender?.name ?? '',
              style: text.labelSmall?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 2),
            Text(message.body, style: text.bodyMedium),
            const SizedBox(height: 4),
            Text(
              Fmt.relative(message.createdAt),
              style: text.labelSmall?.copyWith(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
