import '../models/vocabulary_word.dart';

class SpacedRepetitionService {
  const SpacedRepetitionService();

  /// How soon a forgotten word becomes due again.
  static const Duration forgottenInterval = Duration(minutes: 10);

  /// Interval after the Nth consecutive "Remembered" answer (index = streak-1).
  static const List<Duration> rememberedIntervals = [
    Duration(days: 1),
    Duration(days: 3),
    Duration(days: 7),
    Duration(days: 14),
    Duration(days: 30),
  ];

  static Duration intervalForStreak(int streak) {
    final index = (streak - 1).clamp(0, rememberedIntervals.length - 1);
    return rememberedIntervals[index];
  }

  /// Applies the user's answer and returns the updated word.
  ///
  /// When [isPractice] is true (the user asked to review words that were not
  /// due yet), a "Remembered" answer leaves the schedule untouched so early
  /// reviews can't inflate intervals; "Forgot" still resets the word because
  /// that is genuine signal.
  VocabularyWord recordReview({
    required VocabularyWord word,
    required bool remembered,
    DateTime? reviewedAt,
    bool isPractice = false,
  }) {
    final now = reviewedAt ?? DateTime.now();

    if (!remembered) {
      return word.copyWith(
        lastReviewedAt: now,
        nextReviewAt: now.add(forgottenInterval),
        reviewCount: word.reviewCount + 1,
        forgottenCount: word.forgottenCount + 1,
        streak: 0,
        updatedAt: now,
      );
    }

    if (isPractice) {
      return word;
    }

    final newStreak = word.streak + 1;
    return word.copyWith(
      lastReviewedAt: now,
      nextReviewAt: now.add(intervalForStreak(newStreak)),
      reviewCount: word.reviewCount + 1,
      streak: newStreak,
      updatedAt: now,
    );
  }

  bool isDue(VocabularyWord word, DateTime now) =>
      !word.nextReviewAt.isAfter(now);

  /// Words that are due now, most urgent first: previously forgotten words,
  /// then never-reviewed words, then the most overdue.
  ///
  /// Only due words are returned, so words aren't reviewed before their
  /// interval has elapsed. Because a remembered word is scheduled at least a
  /// day out, it cannot become due again today, while a forgotten word does
  /// become due again after [forgottenInterval].
  List<VocabularyWord> selectDueWords({
    required List<VocabularyWord> allWords,
    required int limit,
    DateTime? now,
  }) {
    if (limit <= 0) return [];
    final currentTime = now ?? DateTime.now();
    final due = allWords.where((w) => isDue(w, currentTime)).toList()
      ..sort(_compareUrgency);
    return due.take(limit).toList();
  }

  /// Words for an explicit extra-practice session when nothing is due:
  /// those whose next review is soonest.
  List<VocabularyWord> selectPracticeWords({
    required List<VocabularyWord> allWords,
    required int limit,
  }) {
    if (limit <= 0) return [];
    final sorted = [...allWords]
      ..sort((a, b) => a.nextReviewAt.compareTo(b.nextReviewAt));
    return sorted.take(limit).toList();
  }

  int countDueWords(List<VocabularyWord> allWords, {DateTime? now}) {
    final currentTime = now ?? DateTime.now();
    return allWords.where((w) => isDue(w, currentTime)).length;
  }

  static int _compareUrgency(VocabularyWord a, VocabularyWord b) {
    int rank(VocabularyWord w) {
      if (w.reviewCount > 0 && w.streak == 0) return 0; // forgotten last time
      if (w.reviewCount == 0) return 1; // new word
      return 2;
    }

    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;
    return a.nextReviewAt.compareTo(b.nextReviewAt);
  }
}
