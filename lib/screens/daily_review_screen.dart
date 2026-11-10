import 'package:flutter/material.dart';

import '../models/vocabulary_word.dart';
import '../state/vocabulary_controller.dart';
import '../theme/app_theme.dart';

class DailyReviewScreen extends StatefulWidget {
  final VocabularyController controller;

  const DailyReviewScreen({super.key, required this.controller});

  @override
  State<DailyReviewScreen> createState() => _DailyReviewScreenState();
}

class _DailyReviewScreenState extends State<DailyReviewScreen> {
  late List<VocabularyWord> _sessionQueue;
  int _currentIndex = 0;
  bool _answerRevealed = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _sessionQueue = widget.controller.buildReviewSessionQueue();
  }

  Future<void> _recordChoice(bool remembered) async {
    if (_isSaving || _currentIndex >= _sessionQueue.length) return;
    setState(() => _isSaving = true);

    final currentWord = _sessionQueue[_currentIndex];
    await widget.controller.recordWordReview(
      word: currentWord,
      remembered: remembered,
    );

    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _answerRevealed = false;
      _currentIndex++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.controller.strings;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final target = widget.controller.settings.dailyReviewTarget;
    final reviewedToday = widget.controller.reviewedTodayCount;

    if (_sessionQueue.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(strings.dailyReviewTitle)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.library_books_rounded,
                  size: 64,
                  color: colorScheme.primary.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  strings.noWordsToReview,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(strings.backToHome),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isFinished = _currentIndex >= _sessionQueue.length;
    if (isFinished) {
      return Scaffold(
        appBar: AppBar(title: Text(strings.dailyReviewTitle)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppTheme.successGreen.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        size: 56,
                        color: AppTheme.successGreen,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      strings.sessionCompleteTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      strings.sessionCompleteSubtitle(_sessionQueue.length),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        strings.reviewProgressText(reviewedToday, target),
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const Key('finish_review_back_button'),
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(strings.backToHome),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final word = _sessionQueue[_currentIndex];
    final sessionProgress = (_currentIndex + 1) / _sessionQueue.length;
    final hasArabic =
        word.arabicMeaning != null && word.arabicMeaning!.trim().isNotEmpty;
    final hasDefinition =
        word.englishDefinition != null &&
        word.englishDefinition!.trim().isNotEmpty;
    final hasExample =
        word.exampleSentence != null && word.exampleSentence!.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.dailyReviewTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(38),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.reviewProgressText(reviewedToday, target),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        '${_currentIndex + 1} / ${_sessionQueue.length}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: sessionProgress,
                    minHeight: 6,
                    backgroundColor: colorScheme.primary.withValues(alpha: 0.14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Main Flashcard
              Expanded(
                child: Card(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 16),
                        // English Word (Always LTR, centered)
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Column(
                            children: [
                              Text(
                                word.word,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.displaySmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              if (word.phonetic != null &&
                                  word.phonetic!.trim().isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  word.phonetic!,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                              if (word.partOfSpeech != null &&
                                  word.partOfSpeech!.trim().isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    word.partOfSpeech!,
                                    style: TextStyle(
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Play Pronunciation Button
                        Center(
                          child: OutlinedButton.icon(
                            key: const Key('review_play_audio_button'),
                            onPressed: () =>
                                widget.controller.playPronunciation(word),
                            icon: const Icon(Icons.volume_up_rounded),
                            label: Text(strings.listenPronunciation),
                          ),
                        ),

                        const SizedBox(height: 28),

                        // Prompt or Revealed Answer
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: !_answerRevealed
                              ? Container(
                                  key: const ValueKey('prompt'),
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHighest
                                        .withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.psychology_outlined,
                                        size: 32,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        strings.thinkAboutMeaning,
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                )
                              : Container(
                                  key: const ValueKey('answer'),
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary.withValues(
                                      alpha: 0.06,
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: colorScheme.primary.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (hasArabic) ...[
                                        RtlText(
                                          word.arabicMeaning!,
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.headlineSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                color: colorScheme.primary,
                                              ),
                                        ),
                                        if (hasDefinition)
                                          const Divider(height: 24),
                                      ],
                                      if (hasDefinition)
                                        LtrText(
                                          word.englishDefinition!,
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.bodyLarge
                                              ?.copyWith(
                                                height: 1.45,
                                                fontWeight: FontWeight.w500,
                                              ),
                                        ),
                                      if (!hasArabic && !hasDefinition)
                                        Text(
                                          strings.notAvailableYet,
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                                fontStyle: FontStyle.italic,
                                              ),
                                        ),
                                      if (hasExample) ...[
                                        const SizedBox(height: 14),
                                        LtrText(
                                          '"${word.exampleSentence!}"',
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                fontStyle: FontStyle.italic,
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Bottom Action Area: "Show Answer" OR "Forgot / Remembered"
              if (!_answerRevealed)
                SizedBox(
                  height: 54,
                  child: FilledButton.icon(
                    key: const Key('show_answer_button'),
                    onPressed: () => setState(() => _answerRevealed = true),
                    icon: const Icon(Icons.visibility_rounded),
                    label: Text(strings.showAnswer),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 60,
                        child: OutlinedButton.icon(
                          key: const Key('forgot_button'),
                          onPressed: _isSaving
                              ? null
                              : () => _recordChoice(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colorScheme.error,
                            side: BorderSide(
                              color: colorScheme.error.withValues(alpha: 0.5),
                              width: 1.5,
                            ),
                          ),
                          icon: const Icon(Icons.replay_rounded),
                          label: Text(
                            strings.forgotButton,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: SizedBox(
                        height: 60,
                        child: FilledButton.icon(
                          key: const Key('remembered_button'),
                          onPressed: _isSaving
                              ? null
                              : () => _recordChoice(true),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.successGreen,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.check_rounded),
                          label: Text(
                            strings.rememberedButton,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
