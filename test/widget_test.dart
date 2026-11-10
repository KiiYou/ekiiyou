import 'package:ekiiyou/data/database_helper.dart';
import 'package:ekiiyou/main.dart';
import 'package:ekiiyou/models/app_settings.dart';
import 'package:ekiiyou/models/vocabulary_word.dart';
import 'package:ekiiyou/services/dictionary_service.dart';
import 'package:ekiiyou/services/spaced_repetition_service.dart';
import 'package:ekiiyou/state/vocabulary_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeTestDictionaryService implements DictionaryService {
  bool simulateOffline = false;
  final Map<String, DictionaryLookupResult> entries = {
    'apple': const DictionaryLookupResult(
      arabicMeaning: 'تفاحة',
      englishDefinition: 'A round fruit with red or green skin.',
      partOfSpeech: 'noun',
      phonetic: '/ˈæp.əl/',
      exampleSentence: 'She ate a crisp red apple.',
      exampleTranslation: 'أكلت تفاحة حمراء مقرمشة.',
      status: InformationStatus.complete,
    ),
    'serendipity': const DictionaryLookupResult(
      arabicMeaning: 'مصادفة سعيدة',
      englishDefinition:
          'The occurrence of events by chance in a happy or beneficial way.',
      partOfSpeech: 'noun',
      phonetic: '/ˌser.ənˈdɪp.ə.ti/',
      exampleSentence: 'Finding that book was pure serendipity.',
      exampleTranslation: 'كان العثور على ذلك الكتاب محض مصادفة سعيدة.',
      status: InformationStatus.complete,
    ),
  };

  @override
  Future<DictionaryLookupResult> lookupWord(String rawWord) async {
    if (simulateOffline) {
      return const DictionaryLookupResult(status: InformationStatus.pending);
    }
    final norm = VocabularyWord.normalize(rawWord);
    return entries[norm] ??
        const DictionaryLookupResult(status: InformationStatus.unavailable);
  }

  @override
  Future<String?> cacheAudioFile(
    String normalizedWord,
    String remoteUrl,
  ) async {
    return null;
  }
}

void main() {
  setUpAll(() {
    DatabaseHelper.ensureInitialized(noIsolate: true);
  });

  group('Normalization & Duplicate Prevention', () {
    test(
      'Normalizes words ignoring capitalization and extra whitespace',
      () async {
        expect(VocabularyWord.normalize('Apple'), 'apple');
        expect(VocabularyWord.normalize('apple'), 'apple');
        expect(VocabularyWord.normalize('  APPLE  '), 'apple');
        expect(VocabularyWord.normalize('Ice   Cream '), 'ice cream');

        final db = DatabaseHelper.forTesting(inMemoryDatabasePath);
        final now = DateTime.now();
        await db.insertWord(
          VocabularyWord(
            word: 'Apple',
            normalizedWord: VocabularyWord.normalize('Apple'),
            arabicMeaning: 'تفاحة',
            createdAt: now,
            updatedAt: now,
            nextReviewAt: now,
            informationStatus: InformationStatus.complete,
          ),
        );

        await expectLater(
          () => db.insertWord(
            VocabularyWord(
              word: ' apple ',
              normalizedWord: VocabularyWord.normalize(' apple '),
              createdAt: now,
              updatedAt: now,
              nextReviewAt: now,
            ),
          ),
          throwsA(isA<DuplicateWordException>()),
        );

        await expectLater(
          () => db.insertWord(
            VocabularyWord(
              word: 'APPLE',
              normalizedWord: VocabularyWord.normalize('APPLE'),
              createdAt: now,
              updatedAt: now,
              nextReviewAt: now,
            ),
          ),
          throwsA(isA<DuplicateWordException>()),
        );

        await db.close();
      },
    );
  });

  group('Spaced Repetition System', () {
    test(
      'Forgotten words reset streak, return sooner, and only due words are selected',
      () {
        const srs = SpacedRepetitionService();
        final now = DateTime(2026, 11, 10, 12, 0);
        final word = VocabularyWord(
          id: 1,
          word: 'resilient',
          normalizedWord: 'resilient',
          createdAt: now,
          updatedAt: now,
          nextReviewAt: now,
        );

        final forgotten = srs.recordReview(
          word: word,
          remembered: false,
          reviewedAt: now,
        );
        final remembered = srs.recordReview(
          word: word,
          remembered: true,
          reviewedAt: now,
        );

        expect(
          forgotten.nextReviewAt.isBefore(remembered.nextReviewAt),
          isTrue,
        );
        expect(forgotten.forgottenCount, 1);
        expect(forgotten.streak, 0);
        expect(remembered.reviewCount, 1);
        expect(remembered.streak, 1);

        // Build a 4-streak word, then forget it -> streak resets to 0, and next
        // remembered answer schedules 1 day out (not 14 or 30 days).
        var progressed = word;
        for (var i = 0; i < 4; i++) {
          progressed = srs.recordReview(
            word: progressed,
            remembered: true,
            reviewedAt: now,
          );
        }
        expect(progressed.streak, 4);

        final lapsed = srs.recordReview(
          word: progressed,
          remembered: false,
          reviewedAt: now,
        );
        expect(lapsed.streak, 0);

        final recovered = srs.recordReview(
          word: lapsed,
          remembered: true,
          reviewedAt: now,
        );
        expect(recovered.streak, 1);
        expect(
          recovered.nextReviewAt.difference(now),
          const Duration(days: 1),
        );

        // Only due words are selected by selectDueWords
        final words = [
          ...List.generate(
            5,
            (i) => VocabularyWord(
              id: i + 1,
              word: 'word$i',
              normalizedWord: 'word$i',
              createdAt: now,
              updatedAt: now,
              nextReviewAt: now,
            ),
          ),
          VocabularyWord(
            id: 99,
            word: 'future',
            normalizedWord: 'future',
            createdAt: now,
            updatedAt: now,
            nextReviewAt: now.add(const Duration(days: 3)),
          ),
        ];
        final session = srs.selectDueWords(
          allWords: words,
          limit: 10,
          now: now,
        );
        expect(session.length, 5);
        expect(session.map((w) => w.id).toSet().length, 5);
        expect(session.any((w) => w.id == 99), isFalse);
      },
    );
  });

  group('Offline Sync, Search, Sort & Full App Flow', () {
    testWidgets(
      'End-to-end flow: Add word, search by English/Arabic, review flashcard, offline sync',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(430, 932));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        SharedPreferences.setMockInitialValues({'language_code': 'en'});
        final db = DatabaseHelper.forTesting(inMemoryDatabasePath);
        final dict = FakeTestDictionaryService();
        final controller = VocabularyController(
          dbHelper: db,
          dictionaryService: dict,
          enableConnectivityListener: false,
        );
        await controller.initialize();

        // Test offline word addition + auto sync when connectivity returns
        dict.simulateOffline = true;
        final pendingWord = await controller.addWord(rawWord: 'serendipity');
        await controller.waitForBackgroundLookups();
        expect(pendingWord.informationStatus, InformationStatus.pending);
        expect(controller.pendingWordsCount, 1);

        dict.simulateOffline = false;
        final syncedCount = await controller.syncPendingWords();
        expect(syncedCount, 1);
        expect(controller.pendingWordsCount, 0);
        expect(
          controller.allWords.first.arabicMeaning,
          equals('مصادفة سعيدة'),
        );

        // Pump the full app widget
        await tester.pumpWidget(SmartVocabularyApp(controller: controller));
        await tester.pumpAndSettle();

        expect(find.text('serendipity'), findsOneWidget);
        expect(find.text('مصادفة سعيدة'), findsOneWidget);

        // Add another word via UI Bottom Sheet (non-blocking save + background enrichment)
        await tester.tap(find.byKey(const Key('home_add_word_button')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('english_word_input')),
          'Apple',
        );
        await tester.tap(find.byKey(const Key('submit_word_button')));
        await tester.pumpAndSettle();
        await controller.waitForBackgroundLookups();
        await tester.pumpAndSettle();

        expect(controller.totalWordsCount, 2);

        // Navigate to My Words tab and test instant search by Arabic (including normalized ه vs ة)
        await tester.tap(find.byKey(const Key('nav_my_words')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('vocabulary_search_field')),
          'تفاحه',
        );
        await tester.pumpAndSettle();
        expect(find.text('Apple'), findsOneWidget);
        expect(find.text('serendipity'), findsNothing);

        await tester.enterText(
          find.byKey(const Key('vocabulary_search_field')),
          '',
        );
        await tester.pumpAndSettle();

        // Test sorting alphabetically
        await controller.setSortOrder(SortOrder.alphabetical);
        await tester.pumpAndSettle();
        expect(controller.filteredWords.first.normalizedWord, 'apple');

        // Navigate back to Home and run a Daily Review flashcard session
        await tester.tap(find.byKey(const Key('nav_home')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('home_start_review_button')));
        await tester.pumpAndSettle();

        // Card 1: Reveal answer and tap Forgot -> re-queued at end of session!
        await tester.tap(find.byKey(const Key('show_answer_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('forgot_button')));
        await tester.pumpAndSettle();

        // Card 2: Reveal answer and tap Remembered
        await tester.tap(find.byKey(const Key('show_answer_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('remembered_button')));
        await tester.pumpAndSettle();

        // Card 3 (the re-queued forgotten card): Reveal answer and tap Remembered
        await tester.tap(find.byKey(const Key('show_answer_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('remembered_button')));
        await tester.pumpAndSettle();

        // Session complete screen
        expect(find.byKey(const Key('finish_review_back_button')), findsOneWidget);
        expect(controller.reviewedTodayCount, 2);

        await tester.tap(find.byKey(const Key('finish_review_back_button')));
        await tester.pumpAndSettle();

        // Test Word Details Screen: open 'Apple', edit its Arabic meaning, then verify
        await tester.tap(find.text('Apple'));
        await tester.pumpAndSettle();

        expect(find.text('She ate a crisp red apple.'), findsNothing);
        expect(find.text('"She ate a crisp red apple."'), findsOneWidget);

        await tester.tap(find.byKey(const Key('edit_word_button')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('arabic_meaning_input')),
          'تفاحة طازجة',
        );
        await tester.tap(find.byKey(const Key('submit_word_button')));
        await tester.pumpAndSettle();

        expect(find.text('تفاحة طازجة'), findsOneWidget);

        // Navigate back from Word Details
        await tester.pageBack();
        await tester.pumpAndSettle();

        // Test Settings Screen: Arabic RTL switch, daily target update, backup/restore & clear all
        await tester.tap(find.byKey(const Key('nav_settings')));
        await tester.pumpAndSettle();

        await controller.updateDailyTarget(15);
        await controller.updateLanguage('ar');
        await tester.pumpAndSettle();

        expect(controller.settings.dailyReviewTarget, 15);
        expect(controller.settings.isArabic, isTrue);
        expect(Directionality.of(tester.element(find.byKey(const Key('nav_settings')))), TextDirection.rtl);

        // Export backup, clear all data, and restore from backup
        final backupJson = await controller.exportBackupJson();
        await controller.clearAllData();
        expect(controller.totalWordsCount, 0);

        final restoredCount = await controller.importBackupJson(backupJson);
        expect(restoredCount, 2);
        expect(controller.totalWordsCount, 2);

        await db.close();
      },
    );

    testWidgets('Splash screen displays EKiiYou logo and transitions to Home', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({'language_code': 'ar'});
      final db = DatabaseHelper.forTesting(inMemoryDatabasePath);
      final controller = VocabularyController(
        dbHelper: db,
        dictionaryService: FakeTestDictionaryService(),
        enableConnectivityListener: false,
      );

      await tester.pumpWidget(
        SmartVocabularyApp(
          controller: controller,
          showSplashOnLaunch: true,
        ),
      );
      expect(find.byType(Image), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('nav_home')), findsOneWidget);
      await db.close();
    });
  });
}
