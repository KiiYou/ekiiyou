# Smart Vocabulary Notebook (دفتر المفردات الذكي)

A clean, lightweight, offline-first mobile application built with Flutter and SQLite that replaces a traditional paper vocabulary notebook.

## Key Features

- **Ultra-Fast Word Entry**: Add a new English word in seconds. The app automatically retrieves its Arabic meaning, simple English definition, part of speech, IPA phonetic transcription, audio pronunciation, and an example sentence with its Arabic translation.
- **Offline-First Architecture**: Powered by a local SQLite database (`sqflite`). Works completely offline—words added without an internet connection are saved immediately with a `pending` status and automatically enriched in the background when connectivity returns.
- **Cached Audio & Offline Pronunciation**: Downloads and caches pronunciation audio files locally for offline playback, with an automatic offline Text-to-Speech (`flutter_tts`) fallback.
- **Smart Duplicate Prevention**: Normalizes words (ignoring case and extra whitespace, e.g., `"Apple"`, `"apple"`, `" APPLE "`) at both the application and database index levels.
- **Instant Local Search & Sorting**: Search instantly by English word, Arabic meaning, or partial match, and sort by Newest, Oldest, or Alphabetical (`A–Z`).
- **Focused Daily Review (Spaced Repetition)**: Simple flashcard review system (`Show Answer` → `Forgot` / `Remembered`). Words forgotten return much sooner; words remembered return at progressively longer intervals (`1d` → `3d` → `7d` → `14d` → `30d`).
- **Daily Reminders**: Local notifications (`flutter_local_notifications`) defaulting to 8:00 PM with customizable reminder time and graceful permission handling.
- **Bilingual Arabic RTL & English LTR Support**: Full Arabic RTL and English LTR interface switching while strictly keeping English vocabulary/definitions in LTR and Arabic meanings/translations in RTL.
