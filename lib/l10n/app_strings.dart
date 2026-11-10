import '../models/vocabulary_word.dart';

class AppStrings {
  final String languageCode;

  const AppStrings(this.languageCode);

  bool get isAr => languageCode == 'ar';

  // App Identity
  String get appTitle => isAr ? 'دفتر المفردات الذكي' : 'Smart Vocab Notebook';

  // Bottom Navigation
  String get navHome => isAr ? 'الرئيسية' : 'Home';
  String get navMyWords => isAr ? 'كلماتي' : 'My Words';
  String get navSettings => isAr ? 'الإعدادات' : 'Settings';

  // Greetings
  String greeting(int hour) {
    if (hour < 12) {
      return isAr ? 'صباح الخير 👋' : 'Good morning 👋';
    } else if (hour < 18) {
      return isAr ? 'مساء الخير 👋' : 'Good afternoon 👋';
    } else {
      return isAr ? 'مساء النور 👋' : 'Good evening 👋';
    }
  }

  String get homeSubtitle => isAr
      ? 'احفظ كلماتك الإنجليزية الجديدة وراجعها يومياً بسهولة'
      : 'Save your new English words and review them daily effortlessly';

  // Home Screen
  String get todayReviewTitle => isAr ? 'مراجعة اليوم' : "Today's Review";
  String reviewProgressText(int reviewed, int target) => isAr
      ? 'تمت مراجعة $reviewed من $target كلمات اليوم'
      : '$reviewed of $target words reviewed today';
  String dueWordsBadge(int count) => isAr
      ? '$count مستحقة للمراجعة'
      : '$count due for review';
  String get startReview => isAr ? 'ابدأ المراجعة' : 'Start Review';
  String get continueReview => isAr ? 'أكمل المراجعة' : 'Continue Review';
  String get reviewMoreWords =>
      isAr ? 'مراجعة كلمات إضافية' : 'Review More Words';
  String get addNewWord => isAr ? 'إضافة كلمة جديدة' : 'Add New Word';
  String get totalSavedWords => isAr ? 'إجمالي الكلمات المحفوظة' : 'Total Saved Words';
  String get pendingSyncWords => isAr ? 'بانتظار الاتصال' : 'Pending Sync';
  String get recentlyAddedWords =>
      isAr ? 'المضافة مؤخراً' : 'Recently Added';
  String get viewAll => isAr ? 'عرض الكل' : 'View All';
  String get noWordsYetTitle =>
      isAr ? 'دفترك فارغ حالياً' : 'Your notebook is empty';
  String get noWordsYetSubtitle => isAr
      ? 'أضف أول كلمة إنجليزية تصادفك اليوم وسنجلب معناها ونطقها تلقائياً.'
      : 'Add your first English word and we will automatically fetch its meaning and pronunciation.';

  // Offline / Sync Banner
  String get offlineBanner => isAr
      ? 'أنت غير متصل بالإنترنت — تُحفظ الكلمات فوراً وسيتم جلب معانيها عند عودة الاتصال'
      : 'Offline mode — Words are saved immediately and enriched when back online';
  String syncingWordsBanner(int count) => isAr
      ? 'جارٍ تحديث بيانات $count كلمة...'
      : 'Updating information for $count word(s)...';
  String get syncNow => isAr ? 'تحديث الآن' : 'Sync Now';

  // Add / Edit Word Sheet
  String get addWordTitle => isAr ? 'إضافة كلمة جديدة' : 'Add New Word';
  String get editWordTitle => isAr ? 'تعديل الكلمة' : 'Edit Word';
  String get englishWordLabel => isAr ? 'الكلمة الإنجليزية' : 'English Word';
  String get englishWordHint =>
      isAr ? 'اكتب الكلمة بالإنجليزية (مثل: serendipity)' : 'Type an English word (e.g., serendipity)';
  String get addButton => isAr ? 'إضافة' : 'Add';
  String get saveChanges => isAr ? 'حفظ التعديلات' : 'Save Changes';
  String get fetchingWordInfo => isAr
      ? 'جارٍ جلب المعنى والتعريف والنطق تلقائياً...'
      : 'Automatically retrieving meaning, definition & pronunciation...';
  String get wordRequiredError =>
      isAr ? 'يرجى كتابة كلمة إنجليزية أولاً' : 'Please enter an English word first';
  String duplicateWordError(String word) => isAr
      ? 'الكلمة "$word" موجودة بالفعل في دفترك!'
      : 'The word "$word" is already in your notebook!';
  String get openExistingWord =>
      isAr ? 'فتح الكلمة الموجودة' : 'Open Existing Word';

  // Manual Fields in Edit Mode
  String get arabicMeaningLabel => isAr ? 'المعنى بالعربية' : 'Arabic Meaning';
  String get englishDefinitionLabel =>
      isAr ? 'التعريف بالإنجليزية (مبسط)' : 'Simple English Definition';
  String get partOfSpeechLabel =>
      isAr ? 'نوع الكلمة (noun, verb...)' : 'Part of Speech (noun, verb...)';
  String get phoneticLabel =>
      isAr ? 'النطق الصوتي (IPA)' : 'Phonetic Pronunciation (IPA)';
  String get exampleSentenceLabel =>
      isAr ? 'جملة مثال بالإنجليزية' : 'Example Sentence';
  String get exampleTranslationLabel =>
      isAr ? 'ترجمة المثال بالعربية' : 'Example Arabic Translation';
  String get manualEntryExpand =>
      isAr ? 'إدخال أو تعديل التفاصيل يدوياً (اختياري)' : 'Enter or edit details manually (optional)';

  // My Words Screen
  String get searchHint => isAr
      ? 'ابحث بالكلمة الإنجليزية أو المعنى العربي...'
      : 'Search by English word or Arabic meaning...';
  String get sortNewest => isAr ? 'الأحدث' : 'Newest';
  String get sortOldest => isAr ? 'الأقدم' : 'Oldest';
  String get sortAlphabetical => isAr ? 'أبجدياً (A-Z)' : 'A–Z';
  String get noSearchResults => isAr
      ? 'لا توجد كلمات مطابقة لبحثك'
      : 'No words match your search';

  // Status labels
  String get statusPending =>
      isAr ? 'بانتظار جلب المعنى' : 'Pending lookup';
  String get statusUnavailable =>
      isAr ? 'المعنى غير متوفر تلقائياً' : 'Dictionary info unavailable';
  String get statusComplete => isAr ? 'مكتمل' : 'Complete';
  String get noArabicMeaningYet =>
      isAr ? 'لم يتم تحديد المعنى العربي بعد' : 'Arabic meaning not set yet';

  // Word Details Screen
  String get wordDetailsTitle => isAr ? 'تفاصيل الكلمة' : 'Word Details';
  String get listenPronunciation => isAr ? 'استماع للنطق' : 'Listen';
  String get cachedOfflineAudio =>
      isAr ? 'محفوظ للاستماع بدون إنترنت' : 'Cached for offline playback';
  String get retryLookup =>
      isAr ? 'إعادة جلب البيانات من القاموس' : 'Retry Dictionary Lookup';
  String get editAction => isAr ? 'تعديل' : 'Edit';
  String get deleteAction => isAr ? 'حذف' : 'Delete';
  String get deleteConfirmTitle => isAr ? 'حذف الكلمة؟' : 'Delete Word?';
  String deleteConfirmMessage(String word) => isAr
      ? 'هل أنت متأكد من حذف "$word" من دفترك؟ لا يمكن التراجع عن هذا الإجراء.'
      : 'Are you sure you want to delete "$word" from your notebook? This cannot be undone.';
  String get cancel => isAr ? 'إلغاء' : 'Cancel';
  String get confirmDelete => isAr ? 'حذف' : 'Delete';
  String get exampleSectionTitle => isAr ? 'مثال توضيحي' : 'Example Sentence';
  String get reviewStatsSectionTitle =>
      isAr ? 'سجل المراجعة' : 'Review Progress';
  String reviewedTimes(int count) =>
      isAr ? 'مرات المراجعة: $count' : 'Reviewed: $count times';
  String forgottenTimes(int count) =>
      isAr ? 'مرات النسيان: $count' : 'Forgot: $count times';
  String get notAvailableYet =>
      isAr ? 'غير متوفر حالياً — يمكنك إضافته يدوياً' : 'Not available yet — tap Edit to add manually';

  // Daily Review Screen
  String get dailyReviewTitle => isAr ? 'المراجعة اليومية' : 'Daily Review';
  String get thinkAboutMeaning => isAr
      ? 'فكّر في معنى هذه الكلمة قبل إظهار الإجابة'
      : 'Think about the meaning of this word before revealing the answer';
  String get showAnswer => isAr ? 'إظهار الإجابة' : 'Show Answer';
  String get forgotButton => isAr ? 'نسيتها' : 'Forgot';
  String get forgotSublabel =>
      isAr ? 'لم أتذكرها (ستعود قريباً)' : "Didn't remember (returns sooner)";
  String get rememberedButton => isAr ? 'تذكرتها' : 'Remembered';
  String get rememberedSublabel =>
      isAr ? 'تذكرتها جيداً' : 'I remembered it';
  String get sessionCompleteTitle =>
      isAr ? 'أحسنت! أكملت جلسة المراجعة 🎉' : 'Great job! Session complete 🎉';
  String sessionCompleteSubtitle(int count) => isAr
      ? 'راجعت $count كلمات في هذه الجلسة. الاستمرارية اليومية هي سر إتقان المفردات!'
      : 'You reviewed $count words in this session. Daily consistency is the key to retention!';
  String get backToHome => isAr ? 'العودة للرئيسية' : 'Back to Home';
  String get noWordsToReview => isAr
      ? 'أضف بعض الكلمات أولاً لتبدأ المراجعة اليومية!'
      : 'Add some words first to start your daily review!';

  // Settings Screen
  String get dailyTargetSetting =>
      isAr ? 'الهدف اليومي للمراجعة' : 'Daily Review Target';
  String wordsPerDay(int count) =>
      isAr ? '$count كلمات يومياً' : '$count words / day';
  String get customTarget => isAr ? 'مخصص' : 'Custom';
  String get customTargetDialogTitle =>
      isAr ? 'تحديد هدف يومي مخصص' : 'Set Custom Daily Target';
  String get customTargetHint =>
      isAr ? 'عدد الكلمات يومياً (1 - 200)' : 'Words per day (1 - 200)';
  String get save => isAr ? 'حفظ' : 'Save';

  String get remindersSection =>
      isAr ? 'التنبيهات والتذكير اليومي' : 'Reminders & Notifications';
  String get dailyReminderToggle =>
      isAr ? 'تفعيل التذكير اليومي' : 'Daily Review Reminder';
  String get reminderTimeLabel => isAr ? 'وقت التذكير' : 'Reminder Time';
  String get notificationPermissionDenied => isAr
      ? 'تم رفض إذن الإشعارات. يرجى تفعيله من إعدادات النظام لتلقي التذكير.'
      : 'Notification permission was denied. Please enable it in system settings.';
  String get notificationTitle =>
      isAr ? 'حان وقت مراجعة كلماتك الإنجليزية!' : 'Time to review your English words!';
  String get notificationBody => isAr
      ? 'خذ دقيقتين الآن لمراجعة مفرداتك اليومية وتثبيتها في ذاكرتك.'
      : 'Take 2 minutes to review your daily vocabulary and keep your streak alive.';

  String get appearanceAndLanguageSection =>
      isAr ? 'اللغة والمظهر' : 'Language & Appearance';
  String get appLanguageLabel => isAr ? 'لغة التطبيق' : 'Application Language';
  String get themeModeLabel => isAr ? 'المظهر' : 'Theme';
  String get themeSystem => isAr ? 'تلقائي (حسب النظام)' : 'System Default';
  String get themeLight => isAr ? 'فاتح' : 'Light';
  String get themeDark => isAr ? 'داكن' : 'Dark';

  String get dataManagementSection =>
      isAr ? 'إدارة البيانات والنسخ الاحتياطي' : 'Data & Backup';
  String get backupDataTitle =>
      isAr ? 'نسخ احتياطي للكلمات (تصدير)' : 'Backup Vocabulary (Export)';
  String get backupDataSubtitle => isAr
      ? 'انسخ بيانات كلماتك للحافظة لحفظها بأمان'
      : 'Copy your vocabulary JSON to clipboard for safekeeping';
  String get restoreDataTitle =>
      isAr ? 'استعادة نسخة احتياطية (استيراد)' : 'Restore Backup (Import)';
  String get restoreDataSubtitle => isAr
      ? 'استرجع كلماتك من نسخة احتياطية سابقة'
      : 'Import words from a previously exported JSON backup';
  String get clearAllDataTitle =>
      isAr ? 'مسح جميع البيانات' : 'Clear All Data';
  String get clearAllDataSubtitle => isAr
      ? 'حذف جميع الكلمات وسجل المراجعة نهائياً'
      : 'Permanently delete all saved words and review progress';
  String get clearAllConfirmTitle =>
      isAr ? 'مسح جميع البيانات؟' : 'Clear All Data?';
  String get clearAllConfirmMessage => isAr
      ? 'سيتم حذف جميع الكلمات المحفوظة وسجل المراجعة نهائياً. لا يمكن التراجع عن هذه الخطوة.'
      : 'All saved words and review history will be permanently deleted. This action cannot be undone.';
  String get confirmClearAll => isAr ? 'مسح الكل' : 'Clear All';

  String get backupCopiedMessage => isAr
      ? 'تم نسخ النسخة الاحتياطية إلى الحافظة بنجاح!'
      : 'Backup JSON copied to clipboard!';
  String restoreSuccessMessage(int count) => isAr
      ? 'تم استيراد $count كلمة بنجاح!'
      : 'Successfully imported $count words!';
  String get restoreDialogHint => isAr
      ? 'الصق نص النسخة الاحتياطية (JSON) هنا:'
      : 'Paste your backup JSON here:';
  String get restoreInvalidError => isAr
      ? 'بيانات النسخة الاحتياطية غير صالحة'
      : 'Invalid backup JSON format';

  String wordAddedToast(String word, InformationStatus status) {
    if (status == InformationStatus.complete) {
      return isAr ? 'تمت إضافة "$word" بنجاح' : 'Added "$word"';
    } else if (status == InformationStatus.pending) {
      return isAr
          ? 'تم حفظ "$word" بدون إنترنت — سيجلب معناها لاحقاً'
          : 'Saved "$word" offline — details will sync when online';
    } else {
      return isAr
          ? 'تم حفظ "$word" (بعض بيانات القاموس غير متوفرة)'
          : 'Saved "$word" (some dictionary details were unavailable)';
    }
  }
}
