import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../models/vocabulary_word.dart';
import '../state/vocabulary_controller.dart';
import '../widgets/add_edit_word_sheet.dart';
import '../widgets/brand_floating_add_button.dart';
import '../widgets/word_list_tile.dart';
import 'word_details_screen.dart';

class MyWordsScreen extends StatefulWidget {
  final VocabularyController controller;

  const MyWordsScreen({super.key, required this.controller});

  @override
  State<MyWordsScreen> createState() => _MyWordsScreenState();
}

class _MyWordsScreenState extends State<MyWordsScreen> {
  late final TextEditingController _searchCtrl;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(text: widget.controller.searchQuery);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openAddWord() async {
    final result = await AddEditWordSheet.show(
      context,
      controller: widget.controller,
    );
    if (result == null || !mounted) return;

    if (result.wasDuplicateOpened && result.word.id != null) {
      _openWordDetails(result.word);
      return;
    }

    final strings = widget.controller.strings;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          strings.wordAddedToast(
            result.word.word,
            result.word.informationStatus,
            isOffline: widget.controller.isOffline,
          ),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openWordDetails(VocabularyWord word) {
    if (word.id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WordDetailsScreen(
          controller: widget.controller,
          wordId: word.id!,
          initialWord: word,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.controller.strings;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final words = widget.controller.filteredWords;
    final totalWords = widget.controller.totalWordsCount;
    final currentSort = widget.controller.sortOrder;

    return Scaffold(
      floatingActionButton: BrandFloatingAddButton(
        key: const Key('my_words_fab_add'),
        onPressed: _openAddWord,
        label: strings.addNewWord,
      ),
      body: Column(
        children: [
          // Search Bar & Sort Chips Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('vocabulary_search_field'),
                  controller: _searchCtrl,
                  onChanged: (value) =>
                      widget.controller.setSearchQuery(value),
                  decoration: InputDecoration(
                    hintText: strings.searchHint,
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              _searchCtrl.clear();
                              widget.controller.setSearchQuery('');
                            },
                            icon: const Icon(Icons.clear_rounded),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _SortChip(
                        label: strings.sortNewest,
                        selected: currentSort == SortOrder.newest,
                        onSelected: () =>
                            widget.controller.setSortOrder(SortOrder.newest),
                      ),
                      const SizedBox(width: 8),
                      _SortChip(
                        label: strings.sortOldest,
                        selected: currentSort == SortOrder.oldest,
                        onSelected: () =>
                            widget.controller.setSortOrder(SortOrder.oldest),
                      ),
                      const SizedBox(width: 8),
                      _SortChip(
                        label: strings.sortAlphabetical,
                        selected: currentSort == SortOrder.alphabetical,
                        onSelected: () => widget.controller.setSortOrder(
                          SortOrder.alphabetical,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Word List or Empty State
          Expanded(
            child: words.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            totalWords == 0
                                ? Icons.menu_book_rounded
                                : Icons.search_off_rounded,
                            size: 56,
                            color: colorScheme.primary.withValues(alpha: 0.45),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            totalWords == 0
                                ? strings.noWordsYetTitle
                                : strings.noSearchResults,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (totalWords == 0) ...[
                            const SizedBox(height: 6),
                            Text(
                              strings.noWordsYetSubtitle,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
                    itemCount: words.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final word = words[index];
                      return WordListTile(
                        word: word,
                        strings: strings,
                        isEnriching: widget.controller.isEnriching(word.id),
                        onTap: () => _openWordDetails(word),
                        onPlayAudio: () =>
                            widget.controller.playPronunciation(word),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _SortChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      selectedColor: colorScheme.primary.withValues(alpha: 0.16),
      labelStyle: TextStyle(
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
      ),
    );
  }
}
