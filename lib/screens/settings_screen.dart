import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/vocabulary_controller.dart';

class SettingsScreen extends StatelessWidget {
  final VocabularyController controller;

  const SettingsScreen({super.key, required this.controller});

  static const List<int> _presetTargets = [5, 10, 15, 20];

  Future<void> _showCustomTargetDialog(BuildContext context) async {
    final strings = controller.strings;
    final textCtrl = TextEditingController(
      text: controller.settings.dailyReviewTarget.toString(),
    );

    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.customTargetDialogTitle),
        content: TextField(
          controller: textCtrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(hintText: strings.customTargetHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(textCtrl.text.trim());
              if (parsed != null && parsed >= 1 && parsed <= 200) {
                Navigator.of(ctx).pop(parsed);
              }
            },
            child: Text(strings.save),
          ),
        ],
      ),
    );

    if (result != null) {
      await controller.updateDailyTarget(result);
    }
  }

  Future<void> _pickReminderTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: controller.settings.reminderTime,
    );
    if (picked != null) {
      await controller.updateReminderTime(picked);
    }
  }

  Future<void> _handleExportBackup(BuildContext context) async {
    final strings = controller.strings;
    final jsonStr = await controller.exportBackupJson();
    await Clipboard.setData(ClipboardData(text: jsonStr));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.backupCopiedMessage),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleImportBackup(BuildContext context) async {
    final strings = controller.strings;
    final textCtrl = TextEditingController();

    final jsonInput = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.restoreDataTitle),
        content: TextField(
          controller: textCtrl,
          maxLines: 6,
          decoration: InputDecoration(hintText: strings.restoreDialogHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(textCtrl.text.trim()),
            child: Text(strings.save),
          ),
        ],
      ),
    );

    if (jsonInput == null || jsonInput.isEmpty || !context.mounted) return;
    try {
      final count = await controller.importBackupJson(jsonInput);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(strings.restoreSuccessMessage(count)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(strings.restoreInvalidError),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _handleClearAllData(BuildContext context) async {
    final strings = controller.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.clearAllConfirmTitle),
        content: Text(strings.clearAllConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(strings.confirmClearAll),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await controller.clearAllData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = controller.strings;
    final settings = controller.settings;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isCustomTarget = !_presetTargets.contains(settings.dailyReviewTarget);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        // 1. Daily Review Target
        _SectionHeader(title: strings.dailyTargetSetting),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  strings.wordsPerDay(settings.dailyReviewTarget),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in _presetTargets)
                      ChoiceChip(
                        label: Text('$preset'),
                        selected: settings.dailyReviewTarget == preset,
                        onSelected: (_) => controller.updateDailyTarget(preset),
                      ),
                    ChoiceChip(
                      label: Text(
                        isCustomTarget
                            ? '${strings.customTarget} (${settings.dailyReviewTarget})'
                            : strings.customTarget,
                      ),
                      selected: isCustomTarget,
                      onSelected: (_) => _showCustomTargetDialog(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 22),

        // 2. Daily Reminders & Notifications
        _SectionHeader(title: strings.remindersSection),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: Text(
                  strings.dailyReminderToggle,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  strings.notificationTitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                value: settings.reminderEnabled,
                onChanged: (enabled) async {
                  final ok = await controller.setReminderEnabled(enabled);
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(strings.notificationPermissionDenied),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  Icons.access_time_rounded,
                  color: colorScheme.primary,
                ),
                title: Text(
                  strings.reminderTimeLabel,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                trailing: TextButton(
                  onPressed: () => _pickReminderTime(context),
                  child: Text(
                    settings.reminderTime.format(context),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                onTap: () => _pickReminderTime(context),
              ),
            ],
          ),
        ),

        const SizedBox(height: 22),

        // 3. Language & Appearance
        _SectionHeader(title: strings.appearanceAndLanguageSection),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(
                  Icons.language_rounded,
                  color: colorScheme.primary,
                ),
                title: Text(
                  strings.appLanguageLabel,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                trailing: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'ar', label: Text('العربية')),
                    ButtonSegment(value: 'en', label: Text('English')),
                  ],
                  selected: {settings.languageCode},
                  onSelectionChanged: (selection) {
                    controller.updateLanguage(selection.first);
                  },
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.brightness_6_rounded,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 16),
                        Text(
                          strings.themeModeLabel,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<ThemeMode>(
                      segments: [
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text(strings.themeSystem),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text(strings.themeLight),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text(strings.themeDark),
                        ),
                      ],
                      selected: {settings.themeMode},
                      onSelectionChanged: (selection) {
                        controller.updateThemeMode(selection.first);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 22),

        // 4. Backup, Restore & Clear All Data
        _SectionHeader(title: strings.dataManagementSection),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(
                  Icons.upload_file_rounded,
                  color: colorScheme.primary,
                ),
                title: Text(
                  strings.backupDataTitle,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(strings.backupDataSubtitle),
                onTap: () => _handleExportBackup(context),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  Icons.download_rounded,
                  color: colorScheme.primary,
                ),
                title: Text(
                  strings.restoreDataTitle,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(strings.restoreDataSubtitle),
                onTap: () => _handleImportBackup(context),
              ),
              const Divider(height: 1),
              ListTile(
                key: const Key('clear_all_data_tile'),
                leading: Icon(
                  Icons.delete_forever_rounded,
                  color: colorScheme.error,
                ),
                title: Text(
                  strings.clearAllDataTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.error,
                  ),
                ),
                subtitle: Text(strings.clearAllDataSubtitle),
                onTap: () => _handleClearAllData(context),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
