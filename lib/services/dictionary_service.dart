import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/vocabulary_word.dart';

class DictionaryLookupResult {
  final String? arabicMeaning;
  final String? englishDefinition;
  final String? partOfSpeech;
  final String? phonetic;
  final String? audioRemoteUrl;
  final String? audioLocalPath;
  final String? exampleSentence;
  final String? exampleTranslation;
  final InformationStatus status;

  const DictionaryLookupResult({
    this.arabicMeaning,
    this.englishDefinition,
    this.partOfSpeech,
    this.phonetic,
    this.audioRemoteUrl,
    this.audioLocalPath,
    this.exampleSentence,
    this.exampleTranslation,
    required this.status,
  });

  bool get hasAnyData =>
      (arabicMeaning != null && arabicMeaning!.isNotEmpty) ||
      (englishDefinition != null && englishDefinition!.isNotEmpty) ||
      (phonetic != null && phonetic!.isNotEmpty) ||
      (audioRemoteUrl != null && audioRemoteUrl!.isNotEmpty);
}

/// Replaceable abstraction for dictionary + Arabic translation lookup.
abstract class DictionaryService {
  Future<DictionaryLookupResult> lookupWord(String rawWord);
  Future<String?> cacheAudioFile(String normalizedWord, String? remoteUrl);
}

class StandardDictionaryService implements DictionaryService {
  final http.Client _client;
  final Duration timeout;
  final String? customCacheDirPath;
  final Map<String, DictionaryLookupResult> _memoryCache = {};

  StandardDictionaryService({
    http.Client? client,
    this.timeout = const Duration(seconds: 7),
    this.customCacheDirPath,
  }) : _client = client ?? http.Client();

  @override
  Future<DictionaryLookupResult> lookupWord(String rawWord) async {
    final normalized = VocabularyWord.normalize(rawWord);
    if (normalized.isEmpty) {
      return const DictionaryLookupResult(
        status: InformationStatus.unavailable,
      );
    }

    final cached = _memoryCache[normalized];
    if (cached != null && cached.status == InformationStatus.complete) {
      return cached;
    }

    bool hadNetworkError = false;

    bool isNetworkError(Object e) =>
        e is SocketException ||
        e is TimeoutException ||
        e is http.ClientException;

    // 1. English dictionary entry (Free Dictionary API).
    Future<_ParsedDictionaryFields?> fetchEntry() async {
      try {
        final uri = Uri.parse(
          'https://api.dictionaryapi.dev/api/v2/entries/en/${Uri.encodeComponent(normalized)}',
        );
        final response = await _client.get(uri).timeout(timeout);
        if (response.statusCode == 200) {
          final decoded = jsonDecode(utf8.decode(response.bodyBytes));
          if (decoded is List && decoded.isNotEmpty) {
            return _parseFreeDictionaryPayload(decoded);
          }
        } else if (response.statusCode >= 500 || response.statusCode == 429) {
          // Server trouble or rate limit: worth retrying later, unlike 404.
          hadNetworkError = true;
        }
      } catch (e) {
        if (isNetworkError(e)) hadNetworkError = true;
      }
      return null;
    }

    // 2. Arabic meaning of the word.
    Future<String?> fetchArabicMeaning() async {
      try {
        final translated = await _translateToArabic(normalized);
        // Ignore results where the service just echoed the English word back.
        if (translated != null &&
            VocabularyWord.normalize(translated) != normalized) {
          return translated;
        }
      } catch (e) {
        if (isNetworkError(e)) hadNetworkError = true;
      }
      return null;
    }

    // The entry and the meaning are independent, so fetch them in parallel.
    final firstWave = await Future.wait<Object?>([
      fetchEntry(),
      fetchArabicMeaning(),
    ]);
    final entry = firstWave[0] as _ParsedDictionaryFields?;
    final arabicMeaning = firstWave[1] as String?;

    final englishDefinition = entry?.englishDefinition;
    final partOfSpeech = entry?.partOfSpeech;
    final phonetic = entry?.phonetic;
    final audioRemoteUrl = entry?.audioRemoteUrl;
    final exampleSentence = entry?.exampleSentence;

    // 3 + 4. Example translation and audio caching both depend on the entry,
    // but not on each other.
    Future<String?> fetchExampleTranslation() async {
      if (exampleSentence == null || exampleSentence.trim().isEmpty) {
        return null;
      }
      try {
        return await _translateToArabic(exampleSentence);
      } catch (e) {
        if (isNetworkError(e)) hadNetworkError = true;
        return null;
      }
    }

    Future<String?> fetchAudio() async {
      return cacheAudioFile(normalized, audioRemoteUrl);
    }

    final secondWave = await Future.wait<String?>([
      fetchExampleTranslation(),
      fetchAudio(),
    ]);
    final exampleTranslation = secondWave[0];
    final audioLocalPath = secondWave[1];

    final hasArabic = arabicMeaning != null && arabicMeaning.isNotEmpty;
    final hasDefinition =
        englishDefinition != null && englishDefinition.isNotEmpty;
    final hasAnyData =
        hasArabic || hasDefinition || (phonetic != null && phonetic.isNotEmpty);

    final InformationStatus status;
    if (hadNetworkError && !(hasArabic && hasDefinition)) {
      // Something is missing because a request failed, not because the data
      // doesn't exist: keep it pending so it is retried automatically.
      status = InformationStatus.pending;
    } else if (hasAnyData) {
      status = InformationStatus.complete;
    } else {
      status = InformationStatus.unavailable;
    }

    final result = DictionaryLookupResult(
      arabicMeaning: arabicMeaning,
      englishDefinition: englishDefinition,
      partOfSpeech: partOfSpeech,
      phonetic: phonetic,
      audioRemoteUrl: audioRemoteUrl,
      audioLocalPath: audioLocalPath,
      exampleSentence: exampleSentence,
      exampleTranslation: exampleTranslation,
      status: status,
    );

    if (status == InformationStatus.complete) {
      _memoryCache[normalized] = result;
    }

    return result;
  }

  _ParsedDictionaryFields _parseFreeDictionaryPayload(List<dynamic> entries) {
    String? phonetic;
    String? audioRemoteUrl;
    String? partOfSpeech;
    String? englishDefinition;
    String? exampleSentence;

    for (final entry in entries) {
      if (entry is! Map) continue;

      if (phonetic == null || phonetic.isEmpty) {
        final topPhonetic = entry['phonetic'];
        if (topPhonetic is String && topPhonetic.trim().isNotEmpty) {
          phonetic = topPhonetic.trim();
        }
      }

      final phoneticsList = entry['phonetics'];
      if (phoneticsList is List) {
        for (final pItem in phoneticsList) {
          if (pItem is! Map) continue;
          if (phonetic == null || phonetic.isEmpty) {
            final text = pItem['text'];
            if (text is String && text.trim().isNotEmpty) {
              phonetic = text.trim();
            }
          }
          if (audioRemoteUrl == null || audioRemoteUrl.isEmpty) {
            final audio = pItem['audio'];
            if (audio is String && audio.trim().isNotEmpty) {
              String url = audio.trim();
              if (url.startsWith('//')) {
                url = 'https:$url';
              }
              audioRemoteUrl = url;
            }
          }
        }
      }

      final meaningsList = entry['meanings'];
      if (meaningsList is List) {
        for (final mItem in meaningsList) {
          if (mItem is! Map) continue;
          final pos = mItem['partOfSpeech'];
          final defs = mItem['definitions'];
          if (defs is List) {
            for (final dItem in defs) {
              if (dItem is! Map) continue;
              final defText = dItem['definition'];
              final exText = dItem['example'];

              if (englishDefinition == null &&
                  defText is String &&
                  defText.trim().isNotEmpty) {
                englishDefinition = defText.trim();
                if (pos is String && pos.trim().isNotEmpty) {
                  partOfSpeech = pos.trim();
                }
              }

              if (exampleSentence == null &&
                  exText is String &&
                  exText.trim().isNotEmpty) {
                exampleSentence = exText.trim();
              }
            }
          }
        }
      }
    }

    return _ParsedDictionaryFields(
      phonetic: phonetic,
      audioRemoteUrl: audioRemoteUrl,
      partOfSpeech: partOfSpeech,
      englishDefinition: englishDefinition,
      exampleSentence: exampleSentence,
    );
  }

  Future<String?> _translateToArabic(String englishText) async {
    // Primary provider: Google Translate GTX endpoint
    try {
      final uri = Uri.parse(
        'https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=ar&dt=t&q=${Uri.encodeComponent(englishText)}',
      );
      final response = await _client.get(uri).timeout(timeout);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is List && decoded.isNotEmpty && decoded[0] is List) {
          final segments = decoded[0] as List;
          final buffer = StringBuffer();
          for (final seg in segments) {
            if (seg is List && seg.isNotEmpty && seg[0] is String) {
              buffer.write(seg[0] as String);
            }
          }
          final result = buffer.toString().trim();
          if (result.isNotEmpty) {
            return result;
          }
        }
      }
    } on SocketException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } on http.ClientException {
      rethrow;
    } catch (_) {}

    // Fallback provider: MyMemory Translation API
    final fallbackUri = Uri.parse(
      'https://api.mymemory.translated.net/get?q=${Uri.encodeComponent(englishText)}&langpair=en|ar',
    );
    final fallbackResponse = await _client.get(fallbackUri).timeout(timeout);
    if (fallbackResponse.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(fallbackResponse.bodyBytes));
      if (decoded is Map && decoded['responseData'] is Map) {
        final translated =
            decoded['responseData']['translatedText'] as String?;
        if (translated != null && translated.trim().isNotEmpty) {
          return translated.trim();
        }
      }
    }
    return null;
  }

  @override
  Future<String?> cacheAudioFile(
    String normalizedWord,
    String? remoteUrl,
  ) async {
    try {
      final String baseDirPath;
      final customPath = customCacheDirPath;
      if (customPath != null) {
        baseDirPath = customPath;
      } else {
        final appDir = await getApplicationDocumentsDirectory();
        baseDirPath = appDir.path;
      }

      final audioDir = Directory(p.join(baseDirPath, 'pronunciation_cache'));
      if (!await audioDir.exists()) {
        await audioDir.create(recursive: true);
      }

      final safeFileName = normalizedWord.replaceAll(
        RegExp(r'[^a-z0-9_-]'),
        '_',
      );
      final filePath = p.join(audioDir.path, '$safeFileName.mp3');
      final file = File(filePath);
      if (await file.exists() && await file.length() > 0) {
        return file.path;
      }

      const audioTimeout = Duration(milliseconds: 3500);

      // 1. Try primary dictionary audio URL if available
      if (remoteUrl != null && remoteUrl.trim().isNotEmpty) {
        try {
          final response = await _client
              .get(Uri.parse(remoteUrl.trim()))
              .timeout(audioTimeout);
          if (response.statusCode == 200 && response.bodyBytes.length > 256) {
            await file.writeAsBytes(response.bodyBytes, flush: true);
            return file.path;
          }
        } catch (_) {}
      }

      // 2. Fallback: high-reliability English TTS MP3 endpoint so every word
      // has a cached offline MP3 file even when the dictionary has no audio.
      final fallbackTtsUri = Uri.parse(
        'https://translate.googleapis.com/translate_tts?ie=UTF-8&client=gtx&tl=en&q=${Uri.encodeComponent(normalizedWord)}',
      );
      final fallbackResp = await _client
          .get(fallbackTtsUri)
          .timeout(audioTimeout);
      if (fallbackResp.statusCode == 200 &&
          fallbackResp.bodyBytes.length > 256) {
        await file.writeAsBytes(fallbackResp.bodyBytes, flush: true);
        return file.path;
      }
    } catch (_) {
      // Caching audio is best-effort; ignore errors so word saving never fails
    }
    return null;
  }
}

class _ParsedDictionaryFields {
  final String? phonetic;
  final String? audioRemoteUrl;
  final String? partOfSpeech;
  final String? englishDefinition;
  final String? exampleSentence;

  const _ParsedDictionaryFields({
    this.phonetic,
    this.audioRemoteUrl,
    this.partOfSpeech,
    this.englishDefinition,
    this.exampleSentence,
  });
}
