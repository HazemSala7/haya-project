import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';

/*
 * The thread between a family and the academy, per child.
 *
 * One thread each, not one inbox: a mother with two children in the academy is
 * having two different conversations with two different specialists, and a
 * single merged list would make her work out which of them «تمام، بنجرّب» was
 * about.
 */
class MessagesScreen extends ConsumerWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);

    return AsyncView(
      value: dashboard,
      onRetry: () => reload(ref, dashboardProvider.future),
      data: (data) {
        final children = J.list(data['children'], (m) => m);

        if (children.isEmpty) {
          return const AppEmpty(
            icon: Icons.forum_outlined,
            title: 'لا توجد محادثات',
            hint: 'المحادثة بتفتح لمّا يرتبط طفلك بالأكاديمية.',
          );
        }

        return RefreshIndicator(
          onRefresh: () => reload(ref, dashboardProvider.future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              for (final child in children)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(
                          builder: (_) => ThreadScreen(
                            studentId: J.int0(child['id']),
                            studentName: J.s(child['name']),
                          ),
                        ))
                        .then((_) => reload(ref, dashboardProvider.future)),
                    child: Row(
                      children: [
                        Avatar(
                          name: J.s(child['name']),
                          seed: J.int0(child['id']),
                          size: 46,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                J.s(child['name']),
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              Text(
                                'محادثة مع فريق الأكاديمية',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_left_rounded,
                            size: 20, color: AppColors.faint),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// One child's thread.
class ThreadScreen extends ConsumerStatefulWidget {
  const ThreadScreen({super.key, required this.studentId, required this.studentName});

  final int studentId;
  final String studentName;

  @override
  ConsumerState<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends ConsumerState<ThreadScreen> {
  final _draft = TextEditingController();
  var _sending = false;

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
          .post('/students/${widget.studentId}/messages', body: {'body': body});
      _draft.clear();
      reload(ref, threadProvider(widget.studentId).future);
      reload(ref, dashboardProvider.future);
    } on ApiException catch (error) {
      if (mounted) showToast(context, error.message, bad: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final thread = ref.watch(threadProvider(widget.studentId));
    final me = ref.watch(meProvider);

    return Scaffold(
      appBar: AppBar(title: Text(widget.studentName)),
      body: Column(
        children: [
          Expanded(
            child: AsyncView(
              value: thread,
              onRetry: () => reload(ref, threadProvider(widget.studentId).future),
              data: (messages) => messages.isEmpty
                  ? const AppEmpty(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: 'ما في رسائل بعد',
                      hint: 'اكتبي أول رسالة للفريق.',
                    )
                  : ListView.builder(
                      // Newest at the bottom, like every thread anyone has
                      // ever read; the API answers newest first.
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      itemCount: messages.length,
                      itemBuilder: (context, i) => _Bubble(
                        message: messages[i],
                        mine: messages[i].sender?.id == me?.id,
                      ),
                    ),
            ),
          ),

          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.lineSoft)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _draft,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(hintText: 'اكتبي رسالتك...'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded, size: 20),
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
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        decoration: BoxDecoration(
          color: mine ? AppColors.brand : AppColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          boxShadow: mine ? null : AppShape.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Whose voice this is. A family thread carries several members of
            // staff, and «من مين هاي؟» is the first thing asked of any of them.
            if (!mine && message.sender != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  message.sender!.name,
                  style: text.labelMedium?.copyWith(color: AppColors.brandDeep),
                ),
              ),

            Text(
              message.body,
              style: text.bodyLarge?.copyWith(
                height: 1.7,
                color: mine ? Colors.white : AppColors.ink,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              Fmt.relative(message.createdAt),
              style: text.labelSmall?.copyWith(
                color: mine ? Colors.white70 : AppColors.faint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
