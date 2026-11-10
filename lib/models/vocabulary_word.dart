enum InformationStatus {
  complete,
  pending,
  unavailable;

  String toJson() => name;

  static InformationStatus fromJson(String? value) {
    switch (value) {
      case 'complete':
        return InformationStatus.complete;
      case 'pending':
        return InformationStatus.pending;
      case 'unavailable':
        return InformationStatus.unavailable;
      default:
        return InformationStatus.pending;
    }
  }
}

class VocabularyWord {
  final int? id;
  final String word;
  final String normalizedWord;
  final String? arabicMeaning;
  final String? englishDefinition;
  final String? partOfSpeech;
  final String? phonetic;
  final String? audioLocalPath;
  final String? audioRemoteUrl;
  final String? exampleSentence;
  final String? exampleTranslation;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastReviewedAt;
  final DateTime nextReviewAt;
  final int reviewCount;
  final int forgottenCount;
  final bool isSynced;
  final InformationStatus informationStatus;

  const VocabularyWord({
    this.id,
    required this.word,
    required this.normalizedWord,
    this.arabicMeaning,
    this.englishDefinition,
    this.partOfSpeech,
    this.phonetic,
    this.audioLocalPath,
    this.audioRemoteUrl,
    this.exampleSentence,
    this.exampleTranslation,
    required this.createdAt,
    required this.updatedAt,
    this.lastReviewedAt,
    required this.nextReviewAt,
    this.reviewCount = 0,
    this.forgottenCount = 0,
    this.isSynced = false,
    this.informationStatus = InformationStatus.pending,
  });

  /// Normalizes a word for duplicate detection: trims and collapses whitespace, lowercases.
  static String normalize(String input) {
    return input.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  bool get hasPronunciationAudio =>
      (audioLocalPath != null && audioLocalPath!.trim().isNotEmpty) ||
      (audioRemoteUrl != null && audioRemoteUrl!.trim().isNotEmpty);

  VocabularyWord copyWith({
    int? id,
    String? word,
    String? normalizedWord,
    String? arabicMeaning,
    bool clearArabicMeaning = false,
    String? englishDefinition,
    bool clearEnglishDefinition = false,
    String? partOfSpeech,
    bool clearPartOfSpeech = false,
    String? phonetic,
    bool clearPhonetic = false,
    String? audioLocalPath,
    bool clearAudioLocalPath = false,
    String? audioRemoteUrl,
    bool clearAudioRemoteUrl = false,
    String? exampleSentence,
    bool clearExampleSentence = false,
    String? exampleTranslation,
    bool clearExampleTranslation = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastReviewedAt,
    DateTime? nextReviewAt,
    int? reviewCount,
    int? forgottenCount,
    bool? isSynced,
    InformationStatus? informationStatus,
  }) {
    final updatedWord = word ?? this.word;
    return VocabularyWord(
      id: id ?? this.id,
      word: updatedWord,
      normalizedWord: normalizedWord ?? VocabularyWord.normalize(updatedWord),
      arabicMeaning: clearArabicMeaning
          ? null
          : (arabicMeaning ?? this.arabicMeaning),
      englishDefinition: clearEnglishDefinition
          ? null
          : (englishDefinition ?? this.englishDefinition),
      partOfSpeech: clearPartOfSpeech
          ? null
          : (partOfSpeech ?? this.partOfSpeech),
      phonetic: clearPhonetic ? null : (phonetic ?? this.phonetic),
      audioLocalPath: clearAudioLocalPath
          ? null
          : (audioLocalPath ?? this.audioLocalPath),
      audioRemoteUrl: clearAudioRemoteUrl
          ? null
          : (audioRemoteUrl ?? this.audioRemoteUrl),
      exampleSentence: clearExampleSentence
          ? null
          : (exampleSentence ?? this.exampleSentence),
      exampleTranslation: clearExampleTranslation
          ? null
          : (exampleTranslation ?? this.exampleTranslation),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
      nextReviewAt: nextReviewAt ?? this.nextReviewAt,
      reviewCount: reviewCount ?? this.reviewCount,
      forgottenCount: forgottenCount ?? this.forgottenCount,
      isSynced: isSynced ?? this.isSynced,
      informationStatus: informationStatus ?? this.informationStatus,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'word': word,
      'normalizedWord': normalizedWord,
      'arabicMeaning': arabicMeaning,
      'englishDefinition': englishDefinition,
      'partOfSpeech': partOfSpeech,
      'phonetic': phonetic,
      'audioLocalPath': audioLocalPath,
      'audioRemoteUrl': audioRemoteUrl,
      'exampleSentence': exampleSentence,
      'exampleTranslation': exampleTranslation,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'lastReviewedAt': lastReviewedAt?.toIso8601String(),
      'nextReviewAt': nextReviewAt.toIso8601String(),
      'reviewCount': reviewCount,
      'forgottenCount': forgottenCount,
      'isSynced': isSynced ? 1 : 0,
      'informationStatus': informationStatus.toJson(),
    };
  }

  factory VocabularyWord.fromMap(Map<String, dynamic> map) {
    final wordText = (map['word'] as String?) ?? '';
    return VocabularyWord(
      id: map['id'] as int?,
      word: wordText,
      normalizedWord:
          (map['normalizedWord'] as String?) ??
          VocabularyWord.normalize(wordText),
      arabicMeaning: map['arabicMeaning'] as String?,
      englishDefinition: map['englishDefinition'] as String?,
      partOfSpeech: map['partOfSpeech'] as String?,
      phonetic: map['phonetic'] as String?,
      audioLocalPath: map['audioLocalPath'] as String?,
      audioRemoteUrl: map['audioRemoteUrl'] as String?,
      exampleSentence: map['exampleSentence'] as String?,
      exampleTranslation: map['exampleTranslation'] as String?,
      createdAt:
          DateTime.tryParse((map['createdAt'] as String?) ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse((map['updatedAt'] as String?) ?? '') ??
          DateTime.now(),
      lastReviewedAt: map['lastReviewedAt'] != null
          ? DateTime.tryParse(map['lastReviewedAt'] as String)
          : null,
      nextReviewAt:
          DateTime.tryParse((map['nextReviewAt'] as String?) ?? '') ??
          DateTime.now(),
      reviewCount: (map['reviewCount'] as int?) ?? 0,
      forgottenCount: (map['forgottenCount'] as int?) ?? 0,
      isSynced: (map['isSynced'] == 1 || map['isSynced'] == true),
      informationStatus: InformationStatus.fromJson(
        map['informationStatus'] as String?,
      ),
    );
  }
}
