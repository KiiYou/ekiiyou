import 'package:flutter/material.dart';

import '../services/native_features_service.dart';
import '../state/vocabulary_controller.dart';
import '../widgets/add_edit_word_sheet.dart';
import 'daily_review_screen.dart';
import 'home_screen.dart';
import 'my_words_screen.dart';
import 'settings_screen.dart';
import 'word_details_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  final VocabularyController controller;

  const MainNavigationScreen({super.key, required this.controller});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.controller.enableConnectivityListener) {
      NativeFeaturesService.instance.onLaunchAction = _handleLaunchAction;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkInitialLaunchAction();
      });
    }
  }

  @override
  void dispose() {
    if (NativeFeaturesService.instance.onLaunchAction == _handleLaunchAction) {
      NativeFeaturesService.instance.onLaunchAction = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.controller.checkDayRollover();
    }
  }

  Future<void> _checkInitialLaunchAction() async {
    final action = await NativeFeaturesService.instance.consumeLaunchAction();
    if (action != null && mounted) {
      _handleLaunchAction(action);
    }
  }

  Future<void> _handleLaunchAction(NativeLaunchAction action) async {
    if (!mounted) return;
    switch (action.action) {
      case 'quick_add':
        setState(() => _selectedIndex = 0);
        final result = await AddEditWordSheet.show(
          context,
          controller: widget.controller,
        );
        if (result != null && mounted) {
          if (result.wasDuplicateOpened && result.word.id != null) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => WordDetailsScreen(
                  controller: widget.controller,
                  wordId: result.word.id!,
                  initialWord: result.word,
                ),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  widget.controller.strings.wordAddedToast(
                    result.word.word,
                    result.word.informationStatus,
                    isOffline: widget.controller.isOffline,
                  ),
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
        break;
      case 'start_review':
        setState(() => _selectedIndex = 0);
        Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => DailyReviewScreen(controller: widget.controller),
          ),
        );
        break;
      case 'open_word':
        final wordId = action.wordId;
        if (wordId != null && wordId > 0) {
          final match = widget.controller.allWords
              .where((w) => w.id == wordId)
              .firstOrNull;
          if (match != null) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => WordDetailsScreen(
                  controller: widget.controller,
                  wordId: wordId,
                  initialWord: match,
                ),
              ),
            );
          }
        }
        break;
    }
  }

  void _navigateToTab(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final strings = widget.controller.strings;
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        final titles = [
          strings.appTitle,
          strings.navMyWords,
          strings.navSettings,
        ];

        final pages = [
          HomeScreen(
            controller: widget.controller,
            onNavigateToMyWords: () => _navigateToTab(1),
            onNavigateToSettings: () => _navigateToTab(2),
          ),
          MyWordsScreen(controller: widget.controller),
          SettingsScreen(controller: widget.controller),
        ];

        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 32,
                    height: 32,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    titles[_selectedIndex],
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            actions: [
              if (widget.controller.pendingWordsCount > 0 &&
                  !widget.controller.isOffline)
                TextButton.icon(
                  onPressed: widget.controller.isSyncingPending
                      ? null
                      : () => widget.controller.syncPendingWords(),
                  icon: widget.controller.isSyncingPending
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_sync_rounded, size: 18),
                  label: Text(
                    widget.controller.isSyncingPending
                        ? strings.syncingWordsBanner(
                            widget.controller.pendingWordsCount,
                          )
                        : strings.syncNow,
                  ),
                ),
            ],
          ),
          body: Column(
            children: [
              if (widget.controller.isOffline)
                Container(
                  width: double.infinity,
                  color: Colors.amber.withValues(alpha: 0.18),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.wifi_off_rounded,
                        size: 16,
                        color: Color(0xFFB45309),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          strings.offlineBanner,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(child: pages[_selectedIndex]),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _navigateToTab,
            destinations: [
              NavigationDestination(
                key: const Key('nav_home'),
                icon: const Icon(Icons.home_outlined),
                selectedIcon: Icon(
                  Icons.home_rounded,
                  color: colorScheme.primary,
                ),
                label: strings.navHome,
              ),
              NavigationDestination(
                key: const Key('nav_my_words'),
                icon: const Icon(Icons.menu_book_outlined),
                selectedIcon: Icon(
                  Icons.menu_book_rounded,
                  color: colorScheme.primary,
                ),
                label: strings.navMyWords,
              ),
              NavigationDestination(
                key: const Key('nav_settings'),
                icon: const Icon(Icons.settings_outlined),
                selectedIcon: Icon(
                  Icons.settings_rounded,
                  color: colorScheme.primary,
                ),
                label: strings.navSettings,
              ),
            ],
          ),
        );
      },
    );
  }
}
