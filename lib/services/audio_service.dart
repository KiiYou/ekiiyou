import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/vocabulary_word.dart';

class AudioPronunciationService {
  AudioPlayer? _audioPlayer;
  FlutterTts? _tts;
  Future<void>? _ttsInitFuture;

  /// Pre-warms the Android/iOS Text-To-Speech engine and AudioPlayer at app
  /// startup so the very first tap on the speaker button is instantaneous.
  Future<void> warmup() async {
    try {
      _audioPlayer ??= AudioPlayer()..setReleaseMode(ReleaseMode.stop);
    } catch (_) {}
    await _ensureTtsReady();
  }

  Future<void> _ensureTtsReady() {
    return _ttsInitFuture ??= _initTts();
  }

  Future<void> _initTts() async {
    try {
      final tts = FlutterTts();
      _tts = tts;
      await tts.awaitSpeakCompletion(false);
      await tts.setLanguage('en-US');
      await tts.setSpeechRate(0.46);
      await tts.setPitch(1.0);
      await tts.setVolume(1.0);
    } catch (_) {
      // Ignore on test/unsupported environments
    }
  }

  /// Plays pronunciation immediately:
  /// 1. If a cached local audio file already exists on disk, plays it right away.
  /// 2. Otherwise (no local file yet), speaks immediately using the pre-warmed
  ///    system TTS instead of blocking on a slow remote network stream.
  Future<bool> playWordPronunciation(VocabularyWord word) async {
    // 1. Play from local disk cache if already downloaded (0 network latency)
    final localPath = word.audioLocalPath;
    if (localPath != null && localPath.trim().isNotEmpty) {
      try {
        final file = File(localPath);
        if (file.existsSync() && file.lengthSync() > 0) {
          _audioPlayer ??= AudioPlayer()..setReleaseMode(ReleaseMode.stop);
          await _tts?.stop();
          await _audioPlayer!
              .play(DeviceFileSource(file.path))
              .timeout(const Duration(milliseconds: 1200));
          return true;
        }
      } catch (_) {
        // Fall through immediately to TTS if the local file failed to play
      }
    }

    // 2. Instant offline Text-To-Speech (never block on remote URL streaming!)
    try {
      await _ensureTtsReady().timeout(const Duration(milliseconds: 800));
      final tts = _tts;
      if (tts != null) {
        await _audioPlayer?.stop();
        await tts.stop();
        await tts.speak(word.word);
        return true;
      }
    } catch (_) {}

    return false;
  }

  Future<void> dispose() async {
    try {
      await _audioPlayer?.dispose();
      await _tts?.stop();
    } catch (_) {}
  }
}
