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
  Future<String?> cacheAudioFile(String normalizedWord, String remoteUrl);
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

    String? englishDefinition;
    String? partOfSpeech;
    String? phonetic;
    String? audioRemoteUrl;
    String? exampleSentence;

    // 1. Fetch English dictionary entry from Free Dictionary API
    try {
      final uri = Uri.parse(
        'https://api.dictionaryapi.dev/api/v2/entries/en/${Uri.encodeComponent(normalized)}',
      );
      final response = await _client.get(uri).timeout(timeout);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is List && decoded.isNotEmpty) {
          final parsed = _parseFreeDictionaryPayload(decoded);
          englishDefinition = parsed.englishDefinition;
          partOfSpeech = parsed.partOfSpeech;
          phonetic = parsed.phonetic;
          audioRemoteUrl = parsed.audioRemoteUrl;
          exampleSentence = parsed.exampleSentence;
        }
      }
    } on SocketException {
      hadNetworkError = true;
    } on TimeoutException {
      hadNetworkError = true;
    } on http.ClientException {
      hadNetworkError = true;
    } catch (_) {
      // Non-fatal parse error; continue to translation lookup
    }

    // 2. Fetch Arabic meaning for the word
    String? arabicMeaning;
    try {
      arabicMeaning = await _translateToArabic(normalized);
      // Avoid setting Arabic meaning if the API echoed the exact English word back
      if (arabicMeaning != null &&
          VocabularyWord.normalize(arabicMeaning) == normalized) {
        arabicMeaning = null;
      }
    } on SocketException {
      hadNetworkError = true;
    } on TimeoutException {
      hadNetworkError = true;
    } on http.ClientException {
      hadNetworkError = true;
    } catch (_) {}

    // 3. Fetch Arabic translation for the example sentence (if available)
    String? exampleTranslation;
    if (exampleSentence != null && exampleSentence.trim().isNotEmpty) {
      try {
        exampleTranslation = await _translateToArabic(exampleSentence);
      } catch (_) {}
    }

    // 4. Download & cache pronunciation audio locally when available
    String? audioLocalPath;
    if (audioRemoteUrl != null && audioRemoteUrl.trim().isNotEmpty) {
      audioLocalPath = await cacheAudioFile(normalized, audioRemoteUrl);
    }

    final hasData = (englishDefinition != null && englishDefinition.isNotEmpty) ||
        (arabicMeaning != null && arabicMeaning.isNotEmpty) ||
        (phonetic != null && phonetic.isNotEmpty);

    final InformationStatus status;
    if (hasData) {
      status = InformationStatus.complete;
    } else if (hadNetworkError) {
      status = InformationStatus.pending;
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
    String remoteUrl,
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

      final response = await _client.get(Uri.parse(remoteUrl)).timeout(timeout);
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(response.bodyBytes, flush: true);
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
