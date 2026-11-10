import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/app_settings.dart';
import '../models/vocabulary_word.dart';

class DuplicateWordException implements Exception {
  final VocabularyWord existingWord;
  const DuplicateWordException(this.existingWord);

  @override
  String toString() =>
      'DuplicateWordException: "${existingWord.word}" already exists.';
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();

  Database? _database;
  final String? _customDbPath;

  DatabaseHelper._internal() : _customDbPath = null;

  static bool _ffiInitialized = false;

  /// Constructor for testing with an isolated or in-memory SQLite database.
  @visibleForTesting
  DatabaseHelper.forTesting(String dbPath) : _customDbPath = dbPath {
    ensureInitialized(noIsolate: true);
  }

  static void ensureInitialized({bool noIsolate = false}) {
    if (_ffiInitialized) return;
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = noIsolate
          ? databaseFactoryFfiNoIsolate
          : databaseFactoryFfi;
      _ffiInitialized = true;
    }
  }

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    ensureInitialized();
    final String dbPath;
    if (_customDbPath != null) {
      dbPath = _customDbPath;
    } else {
      final dir = await getApplicationDocumentsDirectory();
      dbPath = p.join(dir.path, 'smart_vocabulary_notebook.db');
    }

    return openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE vocabulary_words (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            word TEXT NOT NULL,
            normalizedWord TEXT NOT NULL UNIQUE,
            arabicMeaning TEXT,
            englishDefinition TEXT,
            partOfSpeech TEXT,
            phonetic TEXT,
            audioLocalPath TEXT,
            audioRemoteUrl TEXT,
            exampleSentence TEXT,
            exampleTranslation TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            lastReviewedAt TEXT,
            nextReviewAt TEXT NOT NULL,
            reviewCount INTEGER NOT NULL DEFAULT 0,
            forgottenCount INTEGER NOT NULL DEFAULT 0,
            isSynced INTEGER NOT NULL DEFAULT 0,
            informationStatus TEXT NOT NULL DEFAULT 'pending'
          )
        ''');
        await db.execute(
          'CREATE UNIQUE INDEX idx_vocab_normalized ON vocabulary_words(normalizedWord)',
        );
        await db.execute(
          'CREATE INDEX idx_vocab_next_review ON vocabulary_words(nextReviewAt)',
        );
        await db.execute(
          'CREATE INDEX idx_vocab_status ON vocabulary_words(informationStatus)',
        );
      },
    );
  }

  Future<VocabularyWord?> getWordByNormalized(String rawWord) async {
    final db = await database;
    final norm = VocabularyWord.normalize(rawWord);
    if (norm.isEmpty) return null;
    final rows = await db.query(
      'vocabulary_words',
      where: 'normalizedWord = ?',
      whereArgs: [norm],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return VocabularyWord.fromMap(rows.first);
  }

  Future<VocabularyWord?> getWordById(int id) async {
    final db = await database;
    final rows = await db.query(
      'vocabulary_words',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return VocabularyWord.fromMap(rows.first);
  }

  Future<VocabularyWord> insertWord(VocabularyWord word) async {
    final db = await database;
    final normalized = VocabularyWord.normalize(word.word);
    final existing = await getWordByNormalized(normalized);
    if (existing != null) {
      throw DuplicateWordException(existing);
    }

    final cleanedWord = word.word.trim().replaceAll(RegExp(r'\s+'), ' ');
    final toSave = word.copyWith(
      word: cleanedWord,
      normalizedWord: normalized,
    );

    final id = await db.insert(
      'vocabulary_words',
      toSave.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return toSave.copyWith(id: id);
  }

  Future<VocabularyWord> updateWord(VocabularyWord word) async {
    if (word.id == null) {
      throw ArgumentError('Cannot update a word without an id');
    }
    final db = await database;
    final normalized = VocabularyWord.normalize(word.word);
    final existing = await getWordByNormalized(normalized);
    if (existing != null && existing.id != word.id) {
      throw DuplicateWordException(existing);
    }

    final cleanedWord = word.word.trim().replaceAll(RegExp(r'\s+'), ' ');
    final updated = word.copyWith(
      word: cleanedWord,
      normalizedWord: normalized,
      updatedAt: DateTime.now(),
    );

    await db.update(
      'vocabulary_words',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [word.id],
    );
    return updated;
  }

  Future<void> deleteWord(int id) async {
    final db = await database;
    final word = await getWordById(id);
    if (word?.audioLocalPath != null) {
      try {
        final file = File(word!.audioLocalPath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
    await db.delete(
      'vocabulary_words',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<VocabularyWord>> getAllWords({
    String searchQuery = '',
    SortOrder sortOrder = SortOrder.newest,
  }) async {
    final db = await database;
    final trimmedQuery = searchQuery.trim();
    final String orderBy;
    switch (sortOrder) {
      case SortOrder.newest:
        orderBy = 'createdAt DESC, id DESC';
        break;
      case SortOrder.oldest:
        orderBy = 'createdAt ASC, id ASC';
        break;
      case SortOrder.alphabetical:
        orderBy = 'normalizedWord ASC';
        break;
    }

    if (trimmedQuery.isEmpty) {
      final rows = await db.query('vocabulary_words', orderBy: orderBy);
      return rows.map(VocabularyWord.fromMap).toList();
    }

    final normalizedQuery = trimmedQuery.toLowerCase();
    final likePattern = '%$normalizedQuery%';
    final rawLikePattern = '%$trimmedQuery%';

    final rows = await db.query(
      'vocabulary_words',
      where:
          'normalizedWord LIKE ? OR word LIKE ? OR COALESCE(arabicMeaning, \'\') LIKE ?',
      whereArgs: [likePattern, rawLikePattern, rawLikePattern],
      orderBy: orderBy,
    );
    return rows.map(VocabularyWord.fromMap).toList();
  }

  Future<List<VocabularyWord>> getPendingWords() async {
    final db = await database;
    final rows = await db.query(
      'vocabulary_words',
      where: 'informationStatus = ?',
      whereArgs: [InformationStatus.pending.toJson()],
      orderBy: 'createdAt ASC',
    );
    return rows.map(VocabularyWord.fromMap).toList();
  }

  Future<void> clearAllWords() async {
    final db = await database;
    final allWords = await getAllWords();
    for (final w in allWords) {
      if (w.audioLocalPath != null) {
        try {
          final file = File(w.audioLocalPath!);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
    }
    await db.delete('vocabulary_words');
  }

  Future<String> exportAllWordsJson() async {
    final words = await getAllWords(sortOrder: SortOrder.oldest);
    final payload = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'words': words.map((w) => w.toMap()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<int> importWordsJson(String jsonString) async {
    final decoded = jsonDecode(jsonString);
    final List<dynamic> list;
    if (decoded is Map<String, dynamic> && decoded['words'] is List) {
      list = decoded['words'] as List<dynamic>;
    } else if (decoded is List) {
      list = decoded;
    } else {
      throw const FormatException('Invalid backup JSON structure');
    }

    int importedCount = 0;
    for (final item in list) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      map.remove('id');
      final word = VocabularyWord.fromMap(map);
      if (VocabularyWord.normalize(word.word).isEmpty) continue;
      final existing = await getWordByNormalized(word.word);
      if (existing == null) {
        await insertWord(word);
        importedCount++;
      }
    }
    return importedCount;
  }

  Future<void> close() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }
  }
}
