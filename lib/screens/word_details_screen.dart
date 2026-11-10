import 'package:flutter/material.dart';

import '../models/vocabulary_word.dart';
import '../state/vocabulary_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/add_edit_word_sheet.dart';

class WordDetailsScreen extends StatefulWidget {
  final VocabularyController controller;
  final int wordId;
  final VocabularyWord initialWord;

  const WordDetailsScreen({
    super.key,
    required this.controller,
    required this.wordId,
    required this.initialWord,
  });

  @override
  State<WordDetailsScreen> createState() => _WordDetailsScreenState();
}

class _WordDetailsScreenState extends State<WordDetailsScreen> {
  bool _isRetryingLookup = false;

  VocabularyWord _resolveCurrentWord() {
    for (final w in widget.controller.allWords) {
      if (w.id == widget.wordId) return w;
    }
    return widget.initialWord;
  }

  Future<void> _handleEdit(VocabularyWord word) async {
    await AddEditWordSheet.show(
      context,
      controller: widget.controller,
      existingWord: word,
    );
  }

  Future<void> _handleDelete(VocabularyWord word) async {
    final strings = widget.controller.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.deleteConfirmTitle),
        content: Text(strings.deleteConfirmMessage(word.word)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(strings.confirmDelete),
          ),
        ],
      ),
    );

    if (confirmed == true && word.id != null) {
      await widget.controller.deleteWord(word.id!);
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _handleRetryLookup(VocabularyWord word) async {
    setState(() => _isRetryingLookup = true);
    try {
      await widget.controller.retryDictionaryLookup(word);
    } finally {
      if (mounted) {
        setState(() => _isRetryingLookup = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final word = _resolveCurrentWord();
        final strings = widget.controller.strings;
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        final hasArabic =
            word.arabicMeaning != null &&
            word.arabicMeaning!.trim().isNotEmpty;
        final hasDefinition =
            word.englishDefinition != null &&
            word.englishDefinition!.trim().isNotEmpty;
        final hasExample =
            word.exampleSentence != null &&
            word.exampleSentence!.trim().isNotEmpty;
        final hasExampleTrans =
            word.exampleTranslation != null &&
            word.exampleTranslation!.trim().isNotEmpty;

        return Scaffold(
          appBar: AppBar(
            title: Text(strings.wordDetailsTitle),
            actions: [
              IconButton(
                key: const Key('edit_word_button'),
                tooltip: strings.editAction,
                onPressed: () => _handleEdit(word),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                key: const Key('delete_word_button'),
                tooltip: strings.deleteAction,
                onPressed: () => _handleDelete(word),
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: colorScheme.error,
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Hero Card: English Word (LTR), IPA, Part of Speech, Audio Playback
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    word.word,
                                    style: theme.textTheme.headlineMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.3,
                                        ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      if (word.phonetic != null &&
                                          word.phonetic!.trim().isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: colorScheme
                                                .surfaceContainerHighest
                                                .withValues(alpha: 0.6),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            word.phonetic!,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  fontFamily: 'monospace',
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                        ),
                                      if (word.partOfSpeech != null &&
                                          word.partOfSpeech!.trim().isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: colorScheme.primary
                                                .withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            word.partOfSpeech!,
                                            style: TextStyle(
                                              color: colorScheme.primary,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            FilledButton.tonalIcon(
                              key: const Key('play_pronunciation_button'),
                              onPressed: () =>
                                  widget.controller.playPronunciation(word),
                              icon: const Icon(Icons.volume_up_rounded),
                              label: Text(strings.listenPronunciation),
                              style: FilledButton.styleFrom(
                                backgroundColor: colorScheme.primary.withValues(
                                  alpha: 0.14,
                                ),
                                foregroundColor: colorScheme.primary,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (word.audioLocalPath != null &&
                          word.audioLocalPath!.trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(
                              Icons.offline_pin_rounded,
                              size: 15,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              strings.cachedOfflineAudio,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Arabic Meaning Section (Strictly RTL content inside)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.translate_rounded,
                            size: 18,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            strings.arabicMeaningLabel,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (hasArabic)
                        RtlText(
                          word.arabicMeaning!,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.4,
                          ),
                        )
                      else
                        Text(
                          strings.notAvailableYet,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Simple English Definition Section (Strictly LTR content inside)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.menu_book_rounded,
                            size: 18,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              strings.englishDefinitionLabel,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (hasDefinition)
                        LtrText(
                          word.englishDefinition!,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                          ),
                        )
                      else
                        Text(
                          strings.notAvailableYet,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Example Sentence & Arabic Translation Section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.format_quote_rounded,
                            size: 18,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            strings.exampleSectionTitle,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (hasExample) ...[
                        LtrText(
                          '"${word.exampleSentence!}"',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontStyle: FontStyle.italic,
                            height: 1.45,
                          ),
                        ),
                        if (hasExampleTrans) ...[
                          const Divider(height: 20),
                          RtlText(
                            word.exampleTranslation!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.85,
                              ),
                              height: 1.5,
                            ),
                          ),
                        ],
                      ] else
                        Text(
                          strings.notAvailableYet,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Retry Dictionary Lookup button if information is incomplete
              if (!hasArabic ||
                  !hasDefinition ||
                  word.informationStatus != InformationStatus.complete) ...[
                const SizedBox(height: 16),
                Builder(
                  builder: (context) {
                    final isBusy =
                        _isRetryingLookup ||
                        widget.controller.isEnriching(word.id);
                    return OutlinedButton.icon(
                      onPressed: isBusy ? null : () => _handleRetryLookup(word),
                      icon: isBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync_rounded),
                      label: Text(
                        isBusy ? strings.statusEnriching : strings.retryLookup,
                      ),
                    );
                  },
                ),
              ],

              const SizedBox(height: 16),

              // Compact Review Progress Metadata
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      Text(
                        strings.reviewedTimes(word.reviewCount),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        strings.forgottenTimes(word.forgottenCount),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
