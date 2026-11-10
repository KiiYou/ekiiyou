import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/notification_service.dart';
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          strings.customTargetDialogTitle,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        content: TextField(
          controller: textCtrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: strings.customTargetHint,
            prefixIcon: const Icon(Icons.flag_rounded),
          ),
          onSubmitted: (val) {
            final parsed = int.tryParse(val.trim());
            if (parsed != null && parsed >= 1 && parsed <= 200) {
              Navigator.of(ctx).pop(parsed);
            }
          },
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          strings.restoreDataTitle,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null && data!.text!.trim().isNotEmpty) {
                    textCtrl.text = data.text!.trim();
                  }
                },
                icon: const Icon(Icons.content_paste_rounded, size: 18),
                label: Text(strings.pasteFromClipboard),
              ),
            ),
            const SizedBox(height: 6),
            Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(
                controller: textCtrl,
                maxLines: 5,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: InputDecoration(hintText: strings.restoreDialogHint),
              ),
            ),
          ],
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Theme.of(ctx).colorScheme.error,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                strings.clearAllConfirmTitle,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
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
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
      children: [
        // 1. Daily Review Target Card
        _SectionHeader(
          icon: Icons.track_changes_rounded,
          title: strings.dailyTargetSetting,
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _SettingIconBadge(
                      icon: Icons.flag_rounded,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            strings.wordsPerDay(settings.dailyReviewTarget),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            strings.dailyTargetSubtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    for (final preset in _presetTargets) ...[
                      Expanded(
                        child: _TargetOptionTile(
                          label: '$preset',
                          selected: settings.dailyReviewTarget == preset,
                          onTap: () => controller.updateDailyTarget(preset),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      flex: 1,
                      child: _TargetOptionTile(
                        label: isCustomTarget
                            ? '${settings.dailyReviewTarget}'
                            : strings.customTarget,
                        icon: Icons.edit_rounded,
                        selected: isCustomTarget,
                        onTap: () => _showCustomTargetDialog(context),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        // 2. Daily Reminders & Notifications Card
        _SectionHeader(
          icon: Icons.notifications_none_rounded,
          title: strings.remindersSection,
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      _SettingIconBadge(
                        icon: Icons.notifications_active_rounded,
                        color: const Color(0xFFF59E0B),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              strings.dailyReminderToggle,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              strings.notificationTitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Switch(
                        value: settings.reminderEnabled,
                        onChanged: (enabled) async {
                          final result = await controller.setReminderEnabled(
                            enabled,
                          );
                          if (result != ReminderScheduleResult.scheduled &&
                              context.mounted) {
                            final message =
                                result ==
                                    ReminderScheduleResult.permissionDenied
                                ? strings.notificationPermissionDenied
                                : strings.notificationScheduleFailed;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(message),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 12, indent: 16, endIndent: 16),
                InkWell(
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(16),
                  ),
                  onTap: () => _pickReminderTime(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        _SettingIconBadge(
                          icon: Icons.schedule_rounded,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            strings.reminderTimeLabel,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                settings.reminderTime.format(context),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.edit_calendar_rounded,
                                size: 16,
                                color: colorScheme.primary,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        // 3. Language & Appearance Card
        _SectionHeader(
          icon: Icons.palette_outlined,
          title: strings.appearanceAndLanguageSection,
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Application Language Selector
                Row(
                  children: [
                    _SettingIconBadge(
                      icon: Icons.language_rounded,
                      color: const Color(0xFF5B21B6),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        strings.appLanguageLabel,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _VisualChoiceTile(
                        label: 'العربية',
                        icon: Icons.translate_rounded,
                        selected: settings.languageCode == 'ar',
                        onTap: () => controller.updateLanguage('ar'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _VisualChoiceTile(
                        label: 'English',
                        icon: Icons.abc_rounded,
                        selected: settings.languageCode == 'en',
                        onTap: () => controller.updateLanguage('en'),
                      ),
                    ),
                  ],
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Divider(height: 1),
                ),

                // Theme Mode Selector
                Row(
                  children: [
                    _SettingIconBadge(
                      icon: Icons.brightness_6_rounded,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        strings.themeModeLabel,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _VisualChoiceTile(
                        label: strings.themeSystem,
                        icon: Icons.brightness_auto_rounded,
                        selected: settings.themeMode == ThemeMode.system,
                        onTap: () =>
                            controller.updateThemeMode(ThemeMode.system),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _VisualChoiceTile(
                        label: strings.themeLight,
                        icon: Icons.light_mode_rounded,
                        selected: settings.themeMode == ThemeMode.light,
                        onTap: () =>
                            controller.updateThemeMode(ThemeMode.light),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _VisualChoiceTile(
                        label: strings.themeDark,
                        icon: Icons.dark_mode_rounded,
                        selected: settings.themeMode == ThemeMode.dark,
                        onTap: () => controller.updateThemeMode(ThemeMode.dark),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        // 4. Backup & Restore Card
        _SectionHeader(
          icon: Icons.cloud_sync_outlined,
          title: strings.dataManagementSection,
        ),
        const SizedBox(height: 10),
        Card(
          child: Column(
            children: [
              _ActionSettingTile(
                icon: Icons.upload_file_rounded,
                iconColor: colorScheme.primary,
                title: strings.backupDataTitle,
                subtitle: strings.backupDataSubtitle,
                trailingBadge: '${controller.totalWordsCount}',
                onTap: () => _handleExportBackup(context),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _ActionSettingTile(
                icon: Icons.download_rounded,
                iconColor: const Color(0xFF5B21B6),
                title: strings.restoreDataTitle,
                subtitle: strings.restoreDataSubtitle,
                onTap: () => _handleImportBackup(context),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 5. Separated Danger Zone Card (Clear All Data)
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: colorScheme.error.withValues(alpha: 0.28),
              width: 1,
            ),
          ),
          child: _ActionSettingTile(
            tileKey: const Key('clear_all_data_tile'),
            icon: Icons.delete_forever_rounded,
            iconColor: colorScheme.error,
            title: strings.clearAllDataTitle,
            titleColor: colorScheme.error,
            subtitle: strings.clearAllDataSubtitle,
            onTap: () => _handleClearAllData(context),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Icon(icon, size: 17, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _SettingIconBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

class _TargetOptionTile extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const _TargetOptionTile({
    required this.label,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 44,
      decoration: BoxDecoration(
        gradient: selected
            ? const LinearGradient(
                colors: [Color(0xFF1D4ED8), Color(0xFF5B21B6)],
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
              )
            : null,
        color: selected
            ? null
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: selected
            ? null
            : Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: const Color(0xFF1D4ED8).withValues(alpha: 0.24),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(
                        icon,
                        size: 14,
                        color: selected
                            ? Colors.white
                            : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: selected ? Colors.white : colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VisualChoiceTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _VisualChoiceTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
      decoration: BoxDecoration(
        color: selected
            ? colorScheme.primary.withValues(alpha: 0.12)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? colorScheme.primary
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: selected ? 1.6 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 13,
                  color: selected ? colorScheme.primary : colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionSettingTile extends StatelessWidget {
  final Key? tileKey;
  final IconData icon;
  final Color iconColor;
  final String title;
  final Color? titleColor;
  final String subtitle;
  final String? trailingBadge;
  final VoidCallback onTap;

  const _ActionSettingTile({
    this.tileKey,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.titleColor,
    required this.subtitle,
    this.trailingBadge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      key: tileKey,
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            _SettingIconBadge(icon: icon, color: iconColor),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (trailingBadge != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  trailingBadge!,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: iconColor,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}
