import '../models/vocabulary_word.dart';

class SpacedRepetitionService {
  const SpacedRepetitionService();

  /// Applies the user's review outcome (remembered vs forgot) and returns the updated word.
  VocabularyWord recordReview({
    required VocabularyWord word,
    required bool remembered,
    DateTime? reviewedAt,
  }) {
    final now = reviewedAt ?? DateTime.now();
    final newReviewCount = word.reviewCount + 1;

    if (!remembered) {
      // Words the user forgets return much sooner (10 minutes).
      final newForgottenCount = word.forgottenCount + 1;
      return word.copyWith(
        lastReviewedAt: now,
        nextReviewAt: now.add(const Duration(minutes: 10)),
        reviewCount: newReviewCount,
        forgottenCount: newForgottenCount,
        updatedAt: now,
      );
    }

    // Words the user remembers return after a progressively longer interval.
    final netSuccesses = (newReviewCount - word.forgottenCount).clamp(1, 10);
    final Duration nextInterval;
    switch (netSuccesses) {
      case 1:
        nextInterval = const Duration(days: 1);
        break;
      case 2:
        nextInterval = const Duration(days: 3);
        break;
      case 3:
        nextInterval = const Duration(days: 7);
        break;
      case 4:
        nextInterval = const Duration(days: 14);
        break;
      default:
        nextInterval = const Duration(days: 30);
        break;
    }

    return word.copyWith(
      lastReviewedAt: now,
      nextReviewAt: now.add(nextInterval),
      reviewCount: newReviewCount,
      updatedAt: now,
    );
  }

  /// Selects words for a review session without repeating words in the same session.
  /// Prioritizes:
  /// 1. Words due now (`nextReviewAt <= now`), with forgotten & never-reviewed words first.
  /// 2. Words not yet reviewed today if needed to complete the daily target.
  List<VocabularyWord> selectWordsForSession({
    required List<VocabularyWord> allWords,
    required int sessionLimit,
    Set<int> excludeSessionIds = const {},
    Set<int> reviewedTodayIds = const {},
    DateTime? now,
  }) {
    if (allWords.isEmpty || sessionLimit <= 0) return [];
    final currentTime = now ?? DateTime.now();

    final available = allWords
        .where((w) => w.id == null || !excludeSessionIds.contains(w.id))
        .toList();

    // Split into words not yet reviewed today vs already reviewed today
    final notReviewedToday = available
        .where((w) => w.id == null || !reviewedTodayIds.contains(w.id))
        .toList();

    final dueWords = <VocabularyWord>[];
    final upcomingWords = <VocabularyWord>[];

    for (final w in notReviewedToday) {
      if (!w.nextReviewAt.isAfter(currentTime)) {
        dueWords.add(w);
      } else {
        upcomingWords.add(w);
      }
    }

    // Sort due words: newly added or previously forgotten words first, then earliest nextReviewAt
    dueWords.sort((a, b) {
      final aPriority = a.forgottenCount * 2 + (a.reviewCount == 0 ? 1 : 0);
      final bPriority = b.forgottenCount * 2 + (b.reviewCount == 0 ? 1 : 0);
      if (aPriority != bPriority) {
        return bPriority.compareTo(aPriority);
      }
      return a.nextReviewAt.compareTo(b.nextReviewAt);
    });

    // Sort upcoming words by earliest nextReviewAt
    upcomingWords.sort((a, b) => a.nextReviewAt.compareTo(b.nextReviewAt));

    final selected = <VocabularyWord>[...dueWords];
    if (selected.length < sessionLimit) {
      selected.addAll(upcomingWords.take(sessionLimit - selected.length));
    }

    // If the user explicitly starts a bonus review session after reviewing everything today,
    // allow words reviewed earlier today (ordered by earliest nextReviewAt) so the button still works.
    if (selected.isEmpty && available.isNotEmpty) {
      final fallback = [...available]
        ..sort((a, b) => a.nextReviewAt.compareTo(b.nextReviewAt));
      return fallback.take(sessionLimit).toList();
    }

    return selected.take(sessionLimit).toList();
  }

  /// Counts how many words are currently due for review (`nextReviewAt <= now`).
  int countDueWords(List<VocabularyWord> allWords, {DateTime? now}) {
    final currentTime = now ?? DateTime.now();
    return allWords
        .where((w) => !w.nextReviewAt.isAfter(currentTime))
        .length;
  }
}
