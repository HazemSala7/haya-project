import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../auth/session.dart';
import '../models/records.dart';
import '../theme.dart';
import 'ui.dart';

/// A session photo's bytes, fetched with the Authorization header.
///
/// Nothing under /attachments is public — the server checks the viewer against
/// the child's guardians before it streams a byte, and a draft's photos are
/// as invisible to a family as its text. So the image cannot be a plain
/// network URL (an `<img>` sends no header), and the token must never ride in
/// the URL, where it would land in access logs.
///
/// Kept for ten minutes after the last viewer leaves: a parent scrolling a
/// report up and down should not download the same photo five times, and a
/// phone should not hold every photo of the week in memory either.
final attachmentBytesProvider = FutureProvider.autoDispose.family<Uint8List, int>((ref, id) async {
  final link = ref.keepAlive();
  Timer? timer;
  ref.onCancel(() => timer = Timer(const Duration(minutes: 10), link.close));
  ref.onResume(() => timer?.cancel());
  ref.onDispose(() => timer?.cancel());

  return ref.watch(apiProvider).bytes('/attachments/$id');
});

/// A grid of a session's photos and clips.
class AttachmentGrid extends StatelessWidget {
  const AttachmentGrid({super.key, required this.items, this.onLongPress});

  final List<Attachment> items;

  /// Staff who may still edit the report can remove one.
  final void Function(Attachment attachment)? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return AttachmentThumb(
          attachment: item,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => AttachmentViewer(items: items, initial: index)),
          ),
          onLongPress: onLongPress == null ? null : () => onLongPress!(item),
        );
      },
    );
  }
}

class AttachmentThumb extends ConsumerWidget {
  const AttachmentThumb({super.key, required this.attachment, this.onTap, this.onLongPress});

  final Attachment attachment;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget body;

    if (attachment.isVideo) {
      // A clip is not downloaded to draw its tile — it can be twenty
      // megabytes on mobile data. It plays when it is opened.
      body = Container(
        color: AppColors.brandDeep,
        alignment: Alignment.center,
        child: const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 40),
      );
    } else {
      final bytes = ref.watch(attachmentBytesProvider(attachment.id));
      body = bytes.when(
        data: (data) => Image.memory(data, fit: BoxFit.cover, gaplessPlayback: true),
        loading: () => Container(
          color: AppColors.lineSoft,
          alignment: Alignment.center,
          child: const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (_, _) => Container(
          color: AppColors.lineSoft,
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image_outlined, color: AppColors.faint),
        ),
      );
    }

    return ClipRRect(
      borderRadius: AppShape.control,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Stack(fit: StackFit.expand, children: [body]),
        ),
      ),
    );
  }
}

/// Full screen, swipe between a session's photos and clips.
class AttachmentViewer extends StatefulWidget {
  const AttachmentViewer({super.key, required this.items, required this.initial});

  final List<Attachment> items;
  final int initial;

  @override
  State<AttachmentViewer> createState() => _AttachmentViewerState();
}

class _AttachmentViewerState extends State<AttachmentViewer> {
  late final _controller = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.items[_index];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.items.length > 1 ? '${_index + 1} من ${widget.items.length}' : '',
          style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.items.length,
              onPageChanged: (index) => setState(() => _index = index),
              itemBuilder: (context, index) {
                final item = widget.items[index];
                return item.isVideo ? AttachmentVideo(attachment: item) : _FullImage(attachment: item);
              },
            ),
          ),
          if (current.caption != null)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Text(
                  current.caption!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 14, height: 1.6),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FullImage extends ConsumerWidget {
  const _FullImage({required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(attachmentBytesProvider(attachment.id));

    return bytes.when(
      data: (data) => InteractiveViewer(
        maxScale: 5,
        child: Center(child: Image.memory(data, fit: BoxFit.contain)),
      ),
      loading: () => const Center(child: CircularProgressIndicator(color: Colors.white)),
      error: (error, _) => Center(
        child: Text(
          'تعذّر تحميل الصورة.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontFamily: 'Cairo'),
        ),
      ),
    );
  }
}

/// A session clip, streamed from the API with the token in a header.
class AttachmentVideo extends ConsumerStatefulWidget {
  const AttachmentVideo({super.key, required this.attachment});

  final Attachment attachment;

  @override
  ConsumerState<AttachmentVideo> createState() => _AttachmentVideoState();
}

class _AttachmentVideoState extends ConsumerState<AttachmentVideo> {
  VideoPlayerController? _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    final api = ref.read(apiProvider);

    final controller = VideoPlayerController.networkUrl(
      Uri.parse('${api.baseUrl}/attachments/${widget.attachment.id}'),
      httpHeaders: {if (api.token != null) 'Authorization': 'Bearer ${api.token}'},
    );

    _controller = controller;
    controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      controller.play();
    }).catchError((Object error) {
      if (mounted) setState(() => _error = error);
    });
    controller.addListener(_tick);
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.removeListener(_tick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    if (_error != null) {
      return Center(
        child: Text(
          'تعذّر تشغيل الفيديو.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontFamily: 'Cairo'),
        ),
      );
    }

    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    return GestureDetector(
      onTap: () => controller.value.isPlaying ? controller.pause() : controller.play(),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(aspectRatio: controller.value.aspectRatio, child: VideoPlayer(controller)),
          if (!controller.value.isPlaying)
            const Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 72),
          Positioned(
            left: 16,
            right: 16,
            bottom: 12,
            child: VideoProgressIndicator(
              controller,
              allowScrubbing: true,
              colors: const VideoProgressColors(playedColor: AppColors.sky),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ask before removing a photo from a report that has not gone out yet.
Future<bool> confirmRemoveAttachment(BuildContext context) => confirm(
      context,
      title: 'حذف المرفق',
      body: 'بينحذف الملف من الجلسة ومن الخادم. التقرير لسه مسوّدة، فالأهل ما شافوه.',
      confirmLabel: 'احذف',
      danger: true,
    );
