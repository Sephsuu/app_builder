import 'package:flutter/material.dart';
import '../domain/tagalog_transcript_review.dart';

class TranscriptReviewCard extends StatelessWidget {
  const TranscriptReviewCard({
    super.key,
    required this.review,
    required this.current,
    required this.events,
    required this.pending,
    this.onAccept,
    this.onKeep,
    this.onRestore,
    this.onEdit,
  });
  final TagalogTranscriptReview review;
  final String current;
  final List<TranscriptChange> events;
  final bool pending;
  final VoidCallback? onAccept, onKeep, onRestore, onEdit;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tagalog transcript check',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Text(
            pending
                ? 'Check the suggested spelling before translating. Names and meaning need your review.'
                : 'Formatting checked locally. Review names and meaning before translating.',
          ),
          if (pending) ...[
            const SizedBox(height: 8),
            SelectableText(review.suggested),
            for (final change in review.suggestions)
              Text('${change.before} → ${change.after}'),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: onAccept,
                  child: const Text('Use suggested wording'),
                ),
                TextButton(
                  onPressed: onKeep,
                  child: const Text('Keep recognized wording'),
                ),
              ],
            ),
          ],
          ExpansionTile(
            key: PageStorageKey<TagalogTranscriptReview>(review),
            tilePadding: EdgeInsets.zero,
            title: Text('Correction tracker · ${events.length} changes'),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText('Recognized: ${review.raw}'),
              ),
              for (final change in events)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(change.reason),
                  subtitle: Text('${change.before} → ${change.after}'),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText('For translation: $current'),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: onEdit,
                child: const Text('Edit Tagalog wording'),
              ),
              if (current != review.raw.trim())
                TextButton(
                  onPressed: onRestore,
                  child: const Text('Restore recognized text'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
