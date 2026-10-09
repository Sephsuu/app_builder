import 'package:flutter/material.dart';
import '../application/live_recognition.dart';

class LiveCaptionCard extends StatefulWidget {
  const LiveCaptionCard({
    super.key,
    required this.snapshot,
    required this.finalizing,
  });
  final LiveRecognitionSnapshot snapshot;
  final bool finalizing;
  @override
  State<LiveCaptionCard> createState() => _LiveCaptionCardState();
}

class _LiveCaptionCardState extends State<LiveCaptionCard> {
  final _scroll = ScrollController();
  bool _follow = true;
  bool _dragging = false;

  @override
  void didUpdateWidget(covariant LiveCaptionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_follow && widget.snapshot != oldWidget.snapshot) _scrollToLatest();
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _follow && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final empty = snapshot.stable.isEmpty && snapshot.provisional.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.finalizing
              ? 'Reviewing the full recording…'
              : 'Live preview · words may change',
          style: const TextStyle(fontSize: 12, color: Color(0xFF71807A)),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 200,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollStartNotification &&
                  notification.dragDetails != null) {
                _dragging = true;
              }
              if (_dragging) {
                final follow = notification.metrics.extentAfter < 24;
                if (follow != _follow) setState(() => _follow = follow);
              }
              if (notification is ScrollEndNotification) _dragging = false;
              return false;
            },
            child: SingleChildScrollView(
              controller: _scroll,
              child: empty
                  ? const Text(
                      'Listening… Text appears after a few seconds of audio and processing.',
                      style: TextStyle(
                        fontSize: 20,
                        height: 1.5,
                        color: Color(0xFF71807A),
                      ),
                    )
                  : Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: snapshot.stable),
                          TextSpan(
                            text: snapshot.provisional,
                            style: const TextStyle(
                              color: Color(0xFF568E83),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                      style: const TextStyle(
                        fontSize: 24,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF183C38),
                      ),
                    ),
            ),
          ),
        ),
        if (!_follow)
          TextButton.icon(
            onPressed: () {
              setState(() => _follow = true);
              _scrollToLatest();
            },
            icon: const Icon(Icons.arrow_downward_rounded),
            label: const Text('Latest words'),
          ),
        if (snapshot.notice != null)
          Text(snapshot.notice!, style: const TextStyle(fontSize: 12)),
        if (snapshot.processingTime > Duration.zero)
          Text(
            'Last preview: ${(snapshot.processingTime.inMilliseconds / 1000).toStringAsFixed(1)}s processing',
            style: const TextStyle(fontSize: 11, color: Color(0xFF71807A)),
          ),
      ],
    );
  }
}
