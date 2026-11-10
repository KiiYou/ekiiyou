import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/vocabulary_word.dart';
import '../theme/app_theme.dart';

class WordListTile extends StatelessWidget {
  final VocabularyWord word;
  final AppStrings strings;
  final VoidCallback onTap;
  final VoidCallback onPlayAudio;

  const WordListTile({
    super.key,
    required this.word,
    required this.strings,
    required this.onTap,
    required this.onPlayAudio,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasArabic =
        word.arabicMeaning != null && word.arabicMeaning!.trim().isNotEmpty;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Pronunciation button
              IconButton.filledTonal(
                onPressed: onPlayAudio,
                tooltip: strings.listenPronunciation,
                icon: const Icon(Icons.volume_up_rounded, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
                  foregroundColor: colorScheme.primary,
                  minimumSize: const Size(40, 40),
                ),
              ),
              const SizedBox(width: 14),
              // Word & Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top row: English word (strictly LTR) + Part of Speech
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            word.word,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (word.phonetic != null &&
                              word.phonetic!.trim().isNotEmpty)
                            Text(
                              word.phonetic!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (word.partOfSpeech != null &&
                              word.partOfSpeech!.trim().isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.primary.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                word.partOfSpeech!,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Bottom row: Arabic meaning (strictly RTL) or Status badge
                    if (hasArabic)
                      RtlText(
                        word.arabicMeaning!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface.withValues(alpha: 0.88),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    else if (word.englishDefinition != null &&
                        word.englishDefinition!.trim().isNotEmpty)
                      LtrText(
                        word.englishDefinition!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    else
                      _StatusBadge(
                        status: word.informationStatus,
                        strings: strings,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final InformationStatus status;
  final AppStrings strings;

  const _StatusBadge({required this.status, required this.strings});

  @override
  Widget build(BuildContext context) {
    final isPending = status == InformationStatus.pending;
    final color = isPending ? AppTheme.accentAmber : Colors.grey;
    final label = isPending
        ? strings.statusPending
        : strings.statusUnavailable;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isPending
              ? Icons.cloud_sync_outlined
              : Icons.info_outline_rounded,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
