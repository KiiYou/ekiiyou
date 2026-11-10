import 'package:flutter/material.dart';

import '../data/database_helper.dart';
import '../models/vocabulary_word.dart';
import '../state/vocabulary_controller.dart';

class AddEditWordResult {
  final VocabularyWord word;
  final bool wasDuplicateOpened;

  const AddEditWordResult({
    required this.word,
    this.wasDuplicateOpened = false,
  });
}

class AddEditWordSheet extends StatefulWidget {
  final VocabularyController controller;
  final VocabularyWord? existingWord;

  const AddEditWordSheet({
    super.key,
    required this.controller,
    this.existingWord,
  });

  static Future<AddEditWordResult?> show(
    BuildContext context, {
    required VocabularyController controller,
    VocabularyWord? existingWord,
  }) {
    return showModalBottomSheet<AddEditWordResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => AddEditWordSheet(
        controller: controller,
        existingWord: existingWord,
      ),
    );
  }

  @override
  State<AddEditWordSheet> createState() => _AddEditWordSheetState();
}

class _AddEditWordSheetState extends State<AddEditWordSheet> {
  late final TextEditingController _wordCtrl;
  late final TextEditingController _arabicCtrl;
  late final TextEditingController _definitionCtrl;
  late final TextEditingController _posCtrl;
  late final TextEditingController _phoneticCtrl;
  late final TextEditingController _exampleCtrl;
  late final TextEditingController _exampleTransCtrl;

  bool _isSubmitting = false;
  bool _showManualFields = false;
  String? _errorMessage;
  VocabularyWord? _duplicateWord;

  bool get _isEditing => widget.existingWord != null;

  @override
  void initState() {
    super.initState();
    final w = widget.existingWord;
    _wordCtrl = TextEditingController(text: w?.word ?? '');
    _arabicCtrl = TextEditingController(text: w?.arabicMeaning ?? '');
    _definitionCtrl = TextEditingController(text: w?.englishDefinition ?? '');
    _posCtrl = TextEditingController(text: w?.partOfSpeech ?? '');
    _phoneticCtrl = TextEditingController(text: w?.phonetic ?? '');
    _exampleCtrl = TextEditingController(text: w?.exampleSentence ?? '');
    _exampleTransCtrl = TextEditingController(
      text: w?.exampleTranslation ?? '',
    );
    _showManualFields = _isEditing;
  }

  @override
  void dispose() {
    _wordCtrl.dispose();
    _arabicCtrl.dispose();
    _definitionCtrl.dispose();
    _posCtrl.dispose();
    _phoneticCtrl.dispose();
    _exampleCtrl.dispose();
    _exampleTransCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final strings = widget.controller.strings;
    final rawWord = _wordCtrl.text.trim();

    if (rawWord.isEmpty) {
      setState(() {
        _errorMessage = strings.wordRequiredError;
        _duplicateWord = null;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _duplicateWord = null;
    });

    try {
      String? nullIfEmpty(String s) {
        final t = s.trim();
        return t.isEmpty ? null : t;
      }

      if (_isEditing) {
        final existing = widget.existingWord!;
        final updated = existing.copyWith(
          word: rawWord,
          arabicMeaning: nullIfEmpty(_arabicCtrl.text),
          clearArabicMeaning: nullIfEmpty(_arabicCtrl.text) == null,
          englishDefinition: nullIfEmpty(_definitionCtrl.text),
          clearEnglishDefinition: nullIfEmpty(_definitionCtrl.text) == null,
          partOfSpeech: nullIfEmpty(_posCtrl.text),
          clearPartOfSpeech: nullIfEmpty(_posCtrl.text) == null,
          phonetic: nullIfEmpty(_phoneticCtrl.text),
          clearPhonetic: nullIfEmpty(_phoneticCtrl.text) == null,
          exampleSentence: nullIfEmpty(_exampleCtrl.text),
          clearExampleSentence: nullIfEmpty(_exampleCtrl.text) == null,
          exampleTranslation: nullIfEmpty(_exampleTransCtrl.text),
          clearExampleTranslation: nullIfEmpty(_exampleTransCtrl.text) == null,
        );
        final saved = await widget.controller.updateWord(updated);
        if (mounted) {
          Navigator.of(context).pop(AddEditWordResult(word: saved));
        }
      } else {
        final saved = await widget.controller.addWord(
          rawWord: rawWord,
          manualArabicMeaning: nullIfEmpty(_arabicCtrl.text),
          manualEnglishDefinition: nullIfEmpty(_definitionCtrl.text),
          manualPartOfSpeech: nullIfEmpty(_posCtrl.text),
          manualPhonetic: nullIfEmpty(_phoneticCtrl.text),
          manualExampleSentence: nullIfEmpty(_exampleCtrl.text),
          manualExampleTranslation: nullIfEmpty(_exampleTransCtrl.text),
        );
        if (mounted) {
          Navigator.of(context).pop(AddEditWordResult(word: saved));
        }
      }
    } on DuplicateWordException catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _duplicateWord = e.existingWord;
          _errorMessage = strings.duplicateWordError(e.existingWord.word);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.controller.strings;
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: bottomInset + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.3,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _isEditing ? strings.editWordTitle : strings.addWordTitle,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                IconButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // English Word input (always LTR)
            Text(
              strings.englishWordLabel,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(
                key: const Key('english_word_input'),
                controller: _wordCtrl,
                autofocus: !_isEditing,
                enabled: !_isSubmitting,
                textInputAction: _showManualFields
                    ? TextInputAction.next
                    : TextInputAction.done,
                onSubmitted: (_) {
                  if (!_showManualFields && !_isSubmitting) {
                    _submit();
                  }
                },
                decoration: InputDecoration(
                  hintText: strings.englishWordHint,
                  prefixIcon: const Icon(Icons.translate_rounded),
                ),
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          color: theme.colorScheme.error,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_duplicateWord != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop(
                              AddEditWordResult(
                                word: _duplicateWord!,
                                wasDuplicateOpened: true,
                              ),
                            );
                          },
                          icon: const Icon(Icons.open_in_new_rounded, size: 16),
                          label: Text(strings.openExistingWord),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            // Expandable manual fields
            if (!_isEditing && !_showManualFields) ...[
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _isSubmitting
                      ? null
                      : () => setState(() => _showManualFields = true),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: Text(strings.manualEntryExpand),
                ),
              ),
            ],

            if (_showManualFields) ...[
              const SizedBox(height: 14),
              // Arabic Meaning (RTL)
              Text(
                strings.arabicMeaningLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Directionality(
                textDirection: TextDirection.rtl,
                child: TextField(
                  key: const Key('arabic_meaning_input'),
                  controller: _arabicCtrl,
                  enabled: !_isSubmitting,
                  decoration: const InputDecoration(
                    hintText: 'مثال: مصادفة سعيدة',
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Simple English Definition (LTR)
              Text(
                strings.englishDefinitionLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Directionality(
                textDirection: TextDirection.ltr,
                child: TextField(
                  key: const Key('english_definition_input'),
                  controller: _definitionCtrl,
                  enabled: !_isSubmitting,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'The occurrence of events by chance in a happy way',
                  ),
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          strings.partOfSpeechLabel,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: TextField(
                            controller: _posCtrl,
                            enabled: !_isSubmitting,
                            decoration: const InputDecoration(
                              hintText: 'noun, verb...',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          strings.phoneticLabel,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: TextField(
                            controller: _phoneticCtrl,
                            enabled: !_isSubmitting,
                            decoration: const InputDecoration(
                              hintText: '/ˌser.ənˈdɪp.ə.ti/',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Example Sentence (LTR)
              Text(
                strings.exampleSentenceLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Directionality(
                textDirection: TextDirection.ltr,
                child: TextField(
                  controller: _exampleCtrl,
                  enabled: !_isSubmitting,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Finding that book was pure serendipity.',
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Example Arabic Translation (RTL)
              Text(
                strings.exampleTranslationLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Directionality(
                textDirection: TextDirection.rtl,
                child: TextField(
                  controller: _exampleTransCtrl,
                  enabled: !_isSubmitting,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'كان العثور على ذلك الكتاب محض مصادفة سعيدة.',
                  ),
                ),
              ),
            ],

            const SizedBox(height: 18),

            if (_isSubmitting) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        strings.fetchingWordInfo,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              FilledButton.icon(
                key: const Key('submit_word_button'),
                onPressed: _submit,
                icon: Icon(
                  _isEditing ? Icons.check_rounded : Icons.add_rounded,
                ),
                label: Text(
                  _isEditing ? strings.saveChanges : strings.addButton,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
