import 'package:flutter/material.dart';

import '../models/vocabulary_word.dart';
import '../state/vocabulary_controller.dart';
import '../widgets/add_edit_word_sheet.dart';
import '../widgets/word_list_tile.dart';
import 'daily_review_screen.dart';
import 'word_details_screen.dart';

class HomeScreen extends StatelessWidget {
  final VocabularyController controller;
  final VoidCallback onNavigateToMyWords;

  const HomeScreen({
    super.key,
    required this.controller,
    required this.onNavigateToMyWords,
  });

  Future<void> _openAddWord(BuildContext context) async {
    final result = await AddEditWordSheet.show(
      context,
      controller: controller,
    );
    if (result == null || !context.mounted) return;

    if (result.wasDuplicateOpened && result.word.id != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WordDetailsScreen(
            controller: controller,
            wordId: result.word.id!,
            initialWord: result.word,
          ),
        ),
      );
      return;
    }

    final strings = controller.strings;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          strings.wordAddedToast(
            result.word.word,
            result.word.informationStatus,
            isOffline: controller.isOffline,
          ),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openDailyReview(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => DailyReviewScreen(controller: controller),
      ),
    );
  }

  void _openWordDetails(BuildContext context, VocabularyWord word) {
    if (word.id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WordDetailsScreen(
          controller: controller,
          wordId: word.id!,
          initialWord: word,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = controller.strings;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final reviewedToday = controller.reviewedTodayCount;
    final dailyTarget = controller.settings.dailyReviewTarget;
    final progressRatio = dailyTarget > 0
        ? (reviewedToday / dailyTarget).clamp(0.0, 1.0)
        : 0.0;
    final totalWords = controller.totalWordsCount;
    final dueWords = controller.dueWordsCount;
    final recentWords = controller.recentWords;

    final String reviewButtonText;
    if (reviewedToday == 0) {
      reviewButtonText = strings.startReview;
    } else if (reviewedToday < dailyTarget) {
      reviewButtonText = strings.continueReview;
    } else {
      reviewButtonText = strings.reviewMoreWords;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        // 1. Greeting Header
        Text(
          strings.greeting(DateTime.now().hour),
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          strings.homeSubtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),

        // 2. Today's Review Progress & Prominent "Start Review" Button
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFF1D4ED8),
                Color(0xFF5B21B6),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1D4ED8).withValues(alpha: 0.24),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.style_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      strings.todayReviewTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (dueWords > 0) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          strings.dueWordsBadge(dueWords),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              Text(
                strings.reviewProgressText(reviewedToday, dailyTarget),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progressRatio,
                  minHeight: 8,
                  backgroundColor: Colors.white.withValues(alpha: 0.24),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                key: const Key('home_start_review_button'),
                onPressed: totalWords == 0
                    ? () => _openAddWord(context)
                    : () => _openDailyReview(context),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF1D4ED8),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: Icon(
                  totalWords == 0
                      ? Icons.add_rounded
                      : Icons.play_arrow_rounded,
                ),
                label: Text(
                  totalWords == 0 ? strings.addNewWord : reviewButtonText,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // 3. Prominent "Add New Word" Button
        SizedBox(
          height: 54,
          child: OutlinedButton.icon(
            key: const Key('home_add_word_button'),
            onPressed: () => _openAddWord(context),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: colorScheme.primary, width: 1.5),
            ),
            icon: const Icon(Icons.add_circle_outline_rounded),
            label: Text(
              strings.addNewWord,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),

        const SizedBox(height: 20),

        // 4. Total Saved Words Summary Card
        Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onNavigateToMyWords,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.collections_bookmark_rounded,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.totalSavedWords,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$totalWords',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (controller.pendingWordsCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${controller.pendingWordsCount} ${strings.pendingSyncWords}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB45309),
                        ),
                      ),
                    ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 24),

        // 5. Recently Added Words Section
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              strings.recentlyAddedWords,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            if (totalWords > 0)
              TextButton(
                onPressed: onNavigateToMyWords,
                child: Text(strings.viewAll),
              ),
          ],
        ),
        const SizedBox(height: 8),

        if (recentWords.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  Icon(
                    Icons.menu_book_rounded,
                    size: 48,
                    color: colorScheme.primary.withValues(alpha: 0.45),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    strings.noWordsYetTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    strings.noWordsYetSubtitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...recentWords.map(
            (word) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: WordListTile(
                word: word,
                strings: strings,
                isEnriching: controller.isEnriching(word.id),
                onTap: () => _openWordDetails(context, word),
                onPlayAudio: () => controller.playPronunciation(word),
              ),
            ),
          ),
      ],
    );
  }
}
