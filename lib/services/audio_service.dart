import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/vocabulary_word.dart';

class AudioPronunciationService {
  AudioPlayer? _audioPlayer;
  FlutterTts? _tts;
  bool _ttsInitialized = false;

  Future<bool> playWordPronunciation(VocabularyWord word) async {
    // 1. Try cached local audio file first (offline-first)
    if (word.audioLocalPath != null && word.audioLocalPath!.trim().isNotEmpty) {
      try {
        final file = File(word.audioLocalPath!);
        if (await file.exists() && await file.length() > 0) {
          _audioPlayer ??= AudioPlayer();
          await _audioPlayer!.stop();
          await _audioPlayer!.play(DeviceFileSource(file.path));
          return true;
        }
      } catch (_) {}
    }

    // 2. Try remote audio URL if available
    if (word.audioRemoteUrl != null && word.audioRemoteUrl!.trim().isNotEmpty) {
      try {
        _audioPlayer ??= AudioPlayer();
        await _audioPlayer!.stop();
        await _audioPlayer!.play(UrlSource(word.audioRemoteUrl!));
        return true;
      } catch (_) {}
    }

    // 3. Fallback to offline system Text-To-Speech
    try {
      _tts ??= FlutterTts();
      if (!_ttsInitialized) {
        await _tts!.setLanguage('en-US');
        await _tts!.setSpeechRate(0.45);
        _ttsInitialized = true;
      }
      await _tts!.stop();
      await _tts!.speak(word.word);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> dispose() async {
    try {
      await _audioPlayer?.dispose();
      await _tts?.stop();
    } catch (_) {}
  }
}
