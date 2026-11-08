// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appName => 'رفيق';

  @override
  String get needsYourAction => 'يتطلب إجراءً منك';

  @override
  String get dismiss => 'إغلاق';

  @override
  String get undo => 'تراجع';

  @override
  String get clear => 'مسح';

  @override
  String get settings => 'الإعدادات';

  @override
  String get statusReady => 'جاهز للمتابعة';

  @override
  String get statusStopped => 'المتابعة متوقفة';

  @override
  String get statusConnecting => 'جارٍ الاتصال…';

  @override
  String get statusListening => 'يستمع إلى الإمام';

  @override
  String get statusFollowing => 'يتابع الإمام';

  @override
  String get statusFatiha => 'الفاتحة';

  @override
  String get statusNoNewMatch => 'لا تطابق جديد بعد';

  @override
  String get statusLittleSound => 'صوت ضعيف';

  @override
  String get statusNotSure => 'غير متأكد';

  @override
  String get statusNotMatching => 'لا يطابق القرآن';

  @override
  String get statusReconnecting => 'جارٍ إعادة الاتصال…';

  @override
  String get statusStopping => 'جارٍ الإيقاف…';

  @override
  String get captionReady => 'ابدأ المتابعة عندما يبدأ الإمام. لا حاجة لأي إعداد.';

  @override
  String get captionStopped => 'يُعرض آخر موضع.';

  @override
  String get captionConnecting => 'في المرة الأولى، يحمّل خادم التعرّف نموذجه الصوتي.';

  @override
  String get captionListening => 'تظهر الآية بعد بضع كلمات.';

  @override
  String get captionNoNewMatch => 'يصل صوت، لكن لم يُطابَق شيء جديد من القرآن منذ أكثر من 10 ثوانٍ.';

  @override
  String get captionLittleSound => 'لم يلتقط الميكروفون إلا القليل منذ أكثر من 10 ثوانٍ.';

  @override
  String captionStillShowing(int ayah) {
    return 'ما زالت الآية $ayah معروضة.';
  }

  @override
  String captionStillShowingConfirmed(int ayah) {
    return 'ما زالت الآية $ayah، آخر آية مؤكدة، معروضة.';
  }

  @override
  String get captionNotSure => 'تبقى آخر آية مؤكدة معروضة.';

  @override
  String get captionNotMatching => 'تبقى آخر آية مؤكدة معروضة. يحدث هذا أثناء الدعاء أو حين لا تكون الكلمات واضحة.';

  @override
  String get captionReconnecting => 'يواصل الميكروفون الاستماع في الأثناء.';

  @override
  String repeatedText(String refs) {
    return 'نص متكرر — قد يكون أيضًا $refs';
  }

  @override
  String get overlineAyah => 'الآية';

  @override
  String get overlineLastSure => 'آخر موضع مؤكد';

  @override
  String get semNoPosition => 'لا يوجد موضع بعد';

  @override
  String semSurahAyah(String surah, int ayah) {
    return 'سورة $surah، الآية $ayah';
  }

  @override
  String semSurahAyahNotSure(String surah, int ayah) {
    return 'سورة $surah، الآية $ayah، غير متأكد';
  }

  @override
  String get hintOpenSurahList => 'فتح قائمة السور';

  @override
  String get tooltipSurahs => 'السور';

  @override
  String juzNumber(int juz) {
    return 'الجزء $juz';
  }

  @override
  String pageNumber(int page) {
    return 'الصفحة $page';
  }

  @override
  String juzPage(int juz, int page) {
    return 'الجزء $juz · الصفحة $page';
  }

  @override
  String hizbStart(int hizb) {
    return 'الحزب $hizb';
  }

  @override
  String hizbQuarter(int hizb) {
    return 'ربع الحزب $hizb';
  }

  @override
  String hizbHalf(int hizb) {
    return 'نصف الحزب $hizb';
  }

  @override
  String hizbThreeQuarters(int hizb) {
    return 'ثلاثة أرباع الحزب $hizb';
  }

  @override
  String ayahCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count آية',
      many: '$count آية',
      few: '$count آيات',
      two: 'آيتان',
      one: 'آية واحدة',
      zero: 'لا آيات',
    );
    return '$_temp0';
  }

  @override
  String surahHeaderMeta(String name, int number, String ayahs) {
    return '$name · $number · $ayahs';
  }

  @override
  String semSurahHeader(String name, int number) {
    return 'سورة $name، $number';
  }

  @override
  String get tooltipStayOnSurah => 'البقاء في هذه السورة';

  @override
  String tooltipLocked(String scope) {
    return 'مقيّد بـ$scope. المس لإلغاء التقييد.';
  }

  @override
  String get tooltipTonight => 'نقطة بداية الليلة';

  @override
  String get tooltipBackToReading => 'العودة إلى القراءة';

  @override
  String get tooltipRemoveHint => 'إزالة التلميح';

  @override
  String hintTonightSurah(String surah) {
    return 'الليلة: $surah';
  }

  @override
  String hintTonightJuz(int juz) {
    return 'الليلة: الجزء $juz';
  }

  @override
  String lastNightEnded(String place) {
    return 'انتهت صلاة البارحة عند $place.';
  }

  @override
  String get noticePausedTitle => 'المتابعة متوقفة مؤقتًا';

  @override
  String get noticePausedBody => 'انتقل التطبيق إلى الخلفية. يبقى آخر موضع معروضًا.';

  @override
  String get actionResume => 'استئناف';

  @override
  String get actionTryAgain => 'إعادة المحاولة';

  @override
  String get noticeMicPermissionTitle => 'يحتاج رفيق إلى الميكروفون';

  @override
  String get noticeMicPermissionBody =>
      'يستمع إلى تلاوة الإمام ليجد الآية. إن كنت قد رفضت الإذن من قبل، فاسمح به في إعدادات الهاتف: التطبيقات ← رفيق ← الأذونات ← الميكروفون.';

  @override
  String get noticeMicStoppedTitle => 'توقف الميكروفون عن العمل';

  @override
  String get noticeMicStoppedBody =>
      'تعذّر على رفيق استخدام الميكروفون. تأكد من أن تطبيقًا آخر لا يسجّل، ثم أعد المحاولة.';

  @override
  String get noticeUnreachableTitle => 'تعذّر الوصول إلى خادم التعرّف';

  @override
  String get noticeUnreachableBody =>
      'يتعرّف هذا الإصدار على التلاوة عبر حاسوب على شبكة الواي فاي نفسها. تأكد من أنه يعمل ومن صحة العنوان في الإعدادات.';

  @override
  String get actionTestConnection => 'اختبار الاتصال';

  @override
  String get noticeServerStoppedTitle => 'توقف التعرّف';

  @override
  String get emptyListening => 'ضع الهاتف حيث يمكنه سماع الإمام.';

  @override
  String get emptyIdle => 'يستمع رفيق إلى الإمام ويعرض السورة والآية مباشرةً.';

  @override
  String get browseSurahs => 'تصفح السور';

  @override
  String get controlPreparing => 'جارٍ التحضير…';

  @override
  String get controlFinishing => 'جارٍ إنهاء الكلمات الأخيرة…';

  @override
  String get controlStop => 'إيقاف المتابعة';

  @override
  String get controlStart => 'ابدأ المتابعة';

  @override
  String get semStartFollowing => 'ابدأ متابعة الإمام';

  @override
  String get hearingSound => 'يلتقط صوتًا';

  @override
  String get veryLittleSound => 'صوت ضعيف جدًا';

  @override
  String get backToImam => 'العودة إلى الإمام';

  @override
  String backToImamAt(String ref) {
    return 'العودة إلى الإمام · $ref';
  }

  @override
  String ayahSheetTitle(String surah, int ayah) {
    return '$surah · الآية $ayah';
  }

  @override
  String get imamJumpExplanation => 'ينتقل رفيق إلى هذه الآية ويواصل المتابعة منها.';

  @override
  String get startFirstExplanation => 'ابدأ المتابعة أولًا، ثم المس الآية التي يقرؤها الإمام.';

  @override
  String get imamIsHere => 'الإمام هنا';

  @override
  String get unlockAll => 'إلغاء التقييد: البحث في القرآن كله من جديد';

  @override
  String stayOnSurah(String surah) {
    return 'البقاء في $surah';
  }

  @override
  String get stayOnThisSurah => 'البقاء في هذه السورة';

  @override
  String get lockExplanation => 'لن يبحث رفيق في سور أخرى حتى تلغي التقييد. تبقى الفاتحة معروفة في كل ركعة.';

  @override
  String get hintSheetTitle => 'نقطة بداية الليلة';

  @override
  String get hintSheetExplanation => 'اختياري. يجد رفيق الإمام بدونه؛ التلميح يُظهر الآية الأولى أسرع فقط.';

  @override
  String get hintSheetRestarts => 'تغييره يعيد بدء الاستماع.';

  @override
  String get hintNone => 'بدون';

  @override
  String get hintSurah => 'سورة';

  @override
  String get hintJuz => 'جزء';

  @override
  String get hintNoneExplanation => 'بدون تلميح: يبحث رفيق في القرآن كله.';

  @override
  String get searchByNameOrNumber => 'ابحث بالاسم أو الرقم';

  @override
  String get introTitle => 'وضع التراويح';

  @override
  String get introLead => 'يستمع رفيق إلى الإمام ويعرض الآية المتلوّة مباشرةً.';

  @override
  String get introMic => 'لا يُستخدم الميكروفون إلا أثناء المتابعة. وتبقى الشاشة مضاءة.';

  @override
  String get introServer =>
      'يتعرّف هذا الإصدار التجريبي على التلاوة عبر حاسوب على شبكة الواي فاي نفسها (الإعدادات ← خادم التعرّف).';

  @override
  String get introHafs => 'يتابع التلاوة برواية حفص عن عاصم فقط.';

  @override
  String get introCorrect => 'إن أخطأ، فالمس الآية التي يقرؤها الإمام. وحين لا يكون متأكدًا يقول ذلك بدل التخمين.';

  @override
  String get notNow => 'ليس الآن';

  @override
  String semAyah(int ayah) {
    return 'الآية $ayah';
  }

  @override
  String semAyahImamHere(int ayah) {
    return 'الآية $ayah، الإمام هنا';
  }

  @override
  String get hintMarkImam => 'تحديد موضع الإمام';

  @override
  String get hintAyahActions => 'إجراءات الآية';

  @override
  String get tooltipNavigate => 'السور والأجزاء والعلامات';

  @override
  String get tooltipSearch => 'البحث في القرآن';

  @override
  String semReaderBar(String surah, int ayah, int juz, int page) {
    return '$surah، الآية $ayah. الجزء $juz، الصفحة $page. فتح الفهرس';
  }

  @override
  String get taraweeh => 'التراويح';

  @override
  String get semTaraweehEntry => 'التراويح: متابعة الإمام';

  @override
  String get bookmark => 'إضافة علامة';

  @override
  String get removeBookmark => 'إزالة العلامة';

  @override
  String get copyAyah => 'نسخ الآية';

  @override
  String bookmarked(String ref) {
    return 'أُضيفت علامة: $ref';
  }

  @override
  String get bookmarkFailed => 'تعذّر حفظ العلامة. أعد المحاولة.';

  @override
  String get bookmarkRemoved => 'أُزيلت العلامة';

  @override
  String get bookmarkRemoveFailed => 'تعذّرت إزالة العلامة. أعد المحاولة.';

  @override
  String copied(String ref) {
    return 'نُسخت: $ref';
  }

  @override
  String get goTo => 'انتقال إلى';

  @override
  String get tabSurahs => 'السور';

  @override
  String get tabJuz => 'الأجزاء';

  @override
  String get tabPages => 'الصفحات';

  @override
  String get tabBookmarks => 'العلامات';

  @override
  String fromPlacePage(String place, int page) {
    return 'من $place · الصفحة $page';
  }

  @override
  String fromPlaceJuz(String place, int juz) {
    return 'من $place · الجزء $juz';
  }

  @override
  String get whereTaraweehEnded => 'حيث انتهت التراويح';

  @override
  String get today => 'اليوم';

  @override
  String get yesterday => 'أمس';

  @override
  String daysAgo(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'منذ $days يوم',
      many: 'منذ $days يومًا',
      few: 'منذ $days أيام',
      two: 'منذ يومين',
      one: 'منذ يوم',
    );
    return '$_temp0';
  }

  @override
  String get noBookmarks => 'لا توجد علامات بعد. المس آيةً أثناء القراءة لإضافة علامة.';

  @override
  String get searchHint => 'سورة، 2:255، صفحة 50، أو كلمات بالعربية';

  @override
  String searchFirstOf(int shown, int total) {
    return 'أول $shown من $total آية';
  }

  @override
  String searchTooShort(int count) {
    return 'اكتب $count أحرف على الأقل للبحث في النص.';
  }

  @override
  String searchNothing(String query) {
    return 'لا نتائج لـ«$query».';
  }

  @override
  String get searchBy => 'ابحث عن';

  @override
  String get searchHelpSurah => 'سورة: الكهف أو Al-Kahf أو 18';

  @override
  String get searchHelpAyah => 'آية: 2:255';

  @override
  String get searchHelpPlace => 'صفحة أو جزء: صفحة 50، جزء 30';

  @override
  String get searchHelpWords => 'كلمات من القرآن: ٱلْحَمْدُ لِلَّهِ (بالتشكيل أو بدونه)';

  @override
  String surahNumberAyahs(int number, String ayahs) {
    return 'السورة $number · $ayahs';
  }

  @override
  String get groupReading => 'القراءة';

  @override
  String get quranTextSize => 'حجم نص القرآن';

  @override
  String get appearance => 'المظهر';

  @override
  String get appearanceExplanation => 'تتبع القراءة إعداد هاتفك. لوضع التراويح إعداده الخاص أدناه.';

  @override
  String get themeDark => 'داكن';

  @override
  String get themeLight => 'فاتح';

  @override
  String get themeSystem => 'النظام';

  @override
  String get language => 'اللغة';

  @override
  String get languageExplanation => 'يُعرض نص القرآن دائمًا كما أُنزل، بالعربية.';

  @override
  String get languageSystem => 'النظام';

  @override
  String get groupTaraweeh => 'التراويح';

  @override
  String get darkDuringTaraweeh => 'داكن أثناء التراويح';

  @override
  String get darkDuringTaraweehDetail => 'يبقى وضع التراويح داكنًا مهما كان مظهر القراءة';

  @override
  String get keepScreenOn => 'إبقاء الشاشة مضاءة أثناء المتابعة';

  @override
  String get keepScreenOnDetail => 'يُنصح به أثناء الصلاة';

  @override
  String get groupRecitation => 'التلاوة';

  @override
  String get riwaya => 'الرواية';

  @override
  String get hafs => 'حفص عن عاصم';

  @override
  String get hafsOnly => 'يتعرّف رفيق على الآيات ويرقّمها برواية حفص فقط. روايتا قالون وورش غير مدعومتين بعد.';

  @override
  String get groupServer => 'خادم التعرّف';

  @override
  String get serverExplanation => 'يتعرّف هذا الإصدار على التلاوة عبر حاسوب على شبكة الواي فاي نفسها، ولا يعمل بدونه.';

  @override
  String get serverAddress => 'عنوان الخادم';

  @override
  String get serverHelp =>
      'شغّل الخادم على الحاسوب بالأمر:  python -m rafiq_server --host 0.0.0.0\nثم أدخل عنوانه على الواي فاي ومنفذه. على محاكي أندرويد استخدم 10.0.2.2:8765.';

  @override
  String get groupDeveloper => 'المطوّر';

  @override
  String get showDiagnostics => 'عرض التشخيص';

  @override
  String get showDiagnosticsDetail => 'ما يسمعه النموذج الصوتي، للاختبار';

  @override
  String get asrBench => 'اختبار التعرّف على الجهاز';

  @override
  String get asrBenchDetail => 'هل يستطيع هذا الهاتف التعرّف على الإمام دون الحاسوب؟ اختبار وليس ميزة.';

  @override
  String get groupAbout => 'حول التطبيق';

  @override
  String get aboutLead => 'رفيق قارئ للقرآن يستطيع متابعة الإمام في صلاة التراويح وعرض السورة والآية المتلوّة.';

  @override
  String get textSizeSize => 'الحجم';

  @override
  String get textSizeNote => 'تتغير أرقام الآيات والمسافة بين الأسطر مع حجم النص.';

  @override
  String get healthFailed => 'فشل';

  @override
  String healthConnected(int ms, String device) {
    return 'متصل · $ms مللي ثانية · النموذج الصوتي $device';
  }

  @override
  String get healthReadyOnFirstUse => 'جاهز عند أول استخدام';

  @override
  String healthNoAsr(int ms) {
    return 'متصل · $ms مللي ثانية · التعرّف الصوتي غير مثبّت';
  }

  @override
  String get layout => 'طريقة العرض';

  @override
  String get layoutExplanation => 'التمرير: القرآن نصًا متصلًا. الصفحات: صفحات مصحف المدينة الـ604.';

  @override
  String get layoutScroll => 'تمرير';

  @override
  String get layoutPages => 'صفحات';

  @override
  String get tooltipPageView => 'القراءة صفحة صفحة';

  @override
  String get tooltipScrollView => 'القراءة بالتمرير المتصل';

  @override
  String get share => 'مشاركة';

  @override
  String get shareAyah => 'مشاركة الآية';

  @override
  String get shareAsImage => 'مشاركة كصورة';

  @override
  String get shareAsText => 'مشاركة كنص';

  @override
  String get shareFailed => 'تعذّرت المشاركة. أعد المحاولة.';

  @override
  String get dailyGoal => 'هدف القراءة اليومي';

  @override
  String get dailyGoalExplanation =>
      'تُحسب الصفحة إذا بقيت على الشاشة وقتًا يكفي لقراءتها، ثم تؤكّد ذلك بعد القراءة. عشرون صفحة في اليوم جزء كامل: ختمة في شهر.';

  @override
  String get dailyGoalOff => 'بدون';

  @override
  String pagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count صفحة',
      many: '$count صفحة',
      few: '$count صفحات',
      two: 'صفحتان',
      one: 'صفحة واحدة',
    );
    return '$_temp0';
  }

  @override
  String todayProgress(int read, int goal) {
    return 'اليوم $read/$goal';
  }

  @override
  String semTodayProgress(int read, int goal) {
    return 'قُرئت اليوم $read من $goal صفحة';
  }

  @override
  String khatmProgress(int page, int total, int percent) {
    return 'الصفحة $page من $total · $percent٪';
  }

  @override
  String get navRead => 'القراءة';

  @override
  String get navSurahs => 'السور';

  @override
  String get navBookmarks => 'العلامات';

  @override
  String get navMore => 'المزيد';

  @override
  String get continueReading => 'متابعة القراءة';

  @override
  String bookmarksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count علامة',
      many: '$count علامة',
      few: '$count علامات',
      two: 'علامتان',
      one: 'علامة واحدة',
      zero: 'العلامات',
    );
    return '$_temp0';
  }

  @override
  String get sortBookmarks => 'ترتيب العلامات';

  @override
  String get sortNewest => 'الأحدث أولًا';

  @override
  String get sortQuranOrder => 'بترتيب المصحف';

  @override
  String get noBookmarksHint => 'لا توجد علامات بعد. أثناء القراءة، اضغط مطوّلًا على آية لإضافة علامة.';

  @override
  String get scrubberLabel => 'التنقل في القرآن';

  @override
  String get tooltipOpenSurahs => 'السور والأجزاء والصفحات';

  @override
  String get comingSoon => 'قريبًا';

  @override
  String get soon => 'قريبًا';

  @override
  String get soonRecitation => 'التلاوة الصوتية';

  @override
  String get soonRecitationDetail => 'الاستماع إلى آية أو صفحة أو سورة';

  @override
  String get soonOffline => 'التراويح دون حاسوب';

  @override
  String get soonOfflineDetail => 'التعرّف على الهاتف نفسه';

  @override
  String get listen => 'استماع';

  @override
  String get translation => 'ترجمة';

  @override
  String get tafsir => 'تفسير';

  @override
  String get khatmPlanner => 'خطة الختمة';

  @override
  String get khatmPlannerDetail => 'خطط لختمة كاملة وتابعها يومًا بيوم';

  @override
  String get khatmExplanation =>
      'اقرأ القرآن كاملًا قبل تاريخ تختاره. يتكيّف ورد اليوم مع قراءتك: إن سبقتَ خفّ ما بعده.';

  @override
  String get khatmFinishIn => 'أتمّها في';

  @override
  String khatmDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days يوم',
      many: '$days يومًا',
      few: '$days أيام',
      two: 'يومان',
      one: 'يوم واحد',
    );
    return '$_temp0';
  }

  @override
  String get khatmJuzADay => 'جزء كل يوم';

  @override
  String get khatmPickDate => 'اختر تاريخًا';

  @override
  String get khatmLastDay => 'آخر يوم في الختمة';

  @override
  String get khatmStartAt => 'البداية';

  @override
  String get khatmFromHere => 'من حيث أقرأ';

  @override
  String get khatmFromBeginning => 'من البداية';

  @override
  String khatmPreview(int pages, String date) {
    String _temp0 = intl.Intl.pluralLogic(
      pages,
      locale: localeName,
      other: 'نحو $pages صفحة يوميًا',
      many: 'نحو $pages صفحة يوميًا',
      few: 'نحو $pages صفحات يوميًا',
      two: 'نحو صفحتين يوميًا',
      one: 'نحو صفحة واحدة يوميًا',
    );
    return '$_temp0 · تنتهي في $date';
  }

  @override
  String get khatmStart => 'ابدأ الختمة';

  @override
  String khatmPagesRead(int read) {
    return 'قُرئت $read من 604 صفحة';
  }

  @override
  String khatmToday(int read, int target) {
    return 'اليوم: $read من $target صفحة';
  }

  @override
  String khatmDaysLeft(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'بقي $days يوم',
      many: 'بقي $days يومًا',
      few: 'بقيت $days أيام',
      two: 'بقي يومان',
      one: 'اليوم الأخير',
    );
    return '$_temp0';
  }

  @override
  String khatmEnds(String date) {
    return 'تنتهي في $date';
  }

  @override
  String get khatmPastEnd => 'تجاوزتَ تاريخ النهاية';

  @override
  String khatmPagesLeft(int pages) {
    String _temp0 = intl.Intl.pluralLogic(
      pages,
      locale: localeName,
      other: 'بقيت $pages صفحة',
      many: 'بقيت $pages صفحة',
      few: 'بقيت $pages صفحات',
      two: 'بقيت صفحتان',
      one: 'بقيت صفحة واحدة',
    );
    return '$_temp0';
  }

  @override
  String khatmContinue(int page) {
    return 'تابع الختمة (الصفحة $page)';
  }

  @override
  String get khatmChangeEnd => 'غيّر تاريخ النهاية';

  @override
  String get khatmStop => 'أوقف هذه الختمة';

  @override
  String get khatmStopTitle => 'إيقاف هذه الختمة؟';

  @override
  String get khatmStopBody => 'ستُنسى الصفحات المقروءة في هذه الخطة. يبقى سجل قراءتك والختمات المكتملة.';

  @override
  String get khatmStopConfirm => 'أوقف';

  @override
  String get khatmSaveFailed => 'تعذّر حفظ خطة الختمة. حاول مجددًا.';

  @override
  String get khatmFinished => 'الختمات المكتملة';

  @override
  String khatmCompletedOn(String date) {
    return 'اكتملت في $date';
  }

  @override
  String khatmInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'في $days يوم',
      many: 'في $days يومًا',
      few: 'في $days أيام',
      two: 'في يومين',
      one: 'في يوم واحد',
    );
    return '$_temp0';
  }

  @override
  String get khatmComplete => 'اكتملت الختمة';

  @override
  String get khatmSection => 'الختمة';

  @override
  String khatmCard(int read) {
    return '$read من 604 صفحة';
  }

  @override
  String semKhatmToday(int read, int target) {
    return 'الختمة: قُرئت اليوم $read من $target صفحة';
  }

  @override
  String get addNote => 'أضف ملاحظة';

  @override
  String get editNote => 'عدّل الملاحظة';

  @override
  String noteOn(String reference) {
    return 'ملاحظة على $reference';
  }

  @override
  String get noteHint => 'اكتب ملاحظتك';

  @override
  String get saveNote => 'احفظ';

  @override
  String get deleteNote => 'احذف الملاحظة';

  @override
  String get noteSaved => 'حُفظت الملاحظة';

  @override
  String get noteDeleted => 'حُذفت الملاحظة';

  @override
  String get noteSaveFailed => 'تعذّر حفظ الملاحظة. نصّك ما زال هنا.';

  @override
  String get noteDeleteFailed => 'تعذّر حذف الملاحظة.';

  @override
  String get notes => 'الملاحظات';

  @override
  String get semNote => 'ملاحظة';

  @override
  String notesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ملاحظة',
      many: '$count ملاحظة',
      few: '$count ملاحظات',
      two: 'ملاحظتان',
      one: 'ملاحظة واحدة',
      zero: 'الملاحظات',
    );
    return '$_temp0';
  }

  @override
  String get noNotesHint => 'المس آية، ثم «أضف ملاحظة». تظهر ملاحظاتك هنا.';

  @override
  String get reviewTitle => 'هل تُحسب هذه القراءة؟';

  @override
  String get reviewExplanation => 'بقيت هذه الصفحات على الشاشة وقتًا يكفي لقراءتها. ألغِ تحديد ما لم تقرأه.';

  @override
  String reviewCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'احسب $count صفحة',
      many: 'احسب $count صفحة',
      few: 'احسب $count صفحات',
      two: 'احسب صفحتين',
      one: 'احسب صفحة واحدة',
      zero: 'لا تحسب شيئًا',
    );
    return '$_temp0';
  }

  @override
  String get reviewNotNow => 'ليس الآن';

  @override
  String get reviewDiscard => 'لا تحسبها';

  @override
  String reviewCounted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'حُسبت $count صفحة',
      many: 'حُسبت $count صفحة',
      few: 'حُسبت $count صفحات',
      two: 'حُسبت صفحتان',
      one: 'حُسبت صفحة واحدة',
    );
    return '$_temp0';
  }

  @override
  String get reviewFailed => 'تعذّر حفظ قراءتك. ما زالت بانتظار التأكيد؛ حاول مجددًا.';

  @override
  String reviewWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count صفحة بانتظار الحساب',
      many: '$count صفحة بانتظار الحساب',
      few: '$count صفحات بانتظار الحساب',
      two: 'صفحتان بانتظار الحساب',
      one: 'صفحة واحدة بانتظار الحساب',
    );
    return '$_temp0';
  }

  @override
  String get reviewAction => 'راجِع';

  @override
  String get khatmMap => 'الصفحات المقروءة';

  @override
  String get khatmMapHint => 'المس جزءًا لتحديد صفحاته مقروءة أو غير مقروءة: لتصحيح خطأ، أو لإضافة قراءة من مصحف ورقي.';

  @override
  String semJuzTile(int juz, int read, int total) {
    return 'الجزء $juz، قُرئت $read من $total صفحة';
  }

  @override
  String khatmJuzPages(int first, int last, int read, int total) {
    return 'الصفحات $first–$last · قُرئت $read من $total';
  }

  @override
  String get khatmMarkAllRead => 'حدّد الكل مقروءًا';

  @override
  String get khatmMarkAllUnread => 'حدّد الكل غير مقروء';

  @override
  String get translationAndTafsir => 'الترجمة والتفسير';

  @override
  String get translationAndTafsirDetail => 'معاني كل آية، من ناشرين موثوقين';

  @override
  String get chooseTranslation => 'اختر ترجمة';

  @override
  String get chooseTafsir => 'اختر تفسيرًا';

  @override
  String get chooseTextExplanation => 'يُعرض كل نص كما أصدره ناشره دون تغيير.';

  @override
  String get chooseText => 'اختيار النص';

  @override
  String get textLanguageEn => 'الإنجليزية';

  @override
  String get textLanguageFr => 'الفرنسية';

  @override
  String get textLanguageAr => 'العربية';

  @override
  String inLanguage(String language) {
    return 'باللغة $language';
  }

  @override
  String textSourceLine(String credit, String version) {
    return '$credit · الإصدار $version · QuranEnc.com';
  }

  @override
  String get translationNote => 'الترجمة تنقل معاني القرآن، وليست هي القرآن.';

  @override
  String get footnotes => 'الحواشي';

  @override
  String get previousAyah => 'الآية السابقة';

  @override
  String get nextAyah => 'الآية التالية';

  @override
  String get textLoadFailed => 'تعذّر فتح هذا النص. إعادة تثبيت رفيق تصلح ذلك عادةً.';

  @override
  String get listenComingSoon => 'الاستماع إلى التلاوة قريبًا.';

  @override
  String get yourReading => 'قراءتك';

  @override
  String readingRun(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count يوم متتالٍ',
      many: '$count يومًا متتاليًا',
      few: '$count أيام متتالية',
      two: 'يومان متتاليان',
      one: 'يوم واحد متتالٍ',
    );
    return '$_temp0';
  }

  @override
  String get readingRunNone => 'اقرأ صفحة اليوم لتبدأ.';

  @override
  String readingBestRun(String days) {
    return 'الأطول: $days';
  }

  @override
  String daysCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count يوم',
      many: '$count يومًا',
      few: '$count أيام',
      two: 'يومان',
      one: 'يوم واحد',
    );
    return '$_temp0';
  }

  @override
  String daysReadThisYear(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count يوم قراءة هذا العام',
      many: '$count يوم قراءة هذا العام',
      few: '$count أيام قراءة هذا العام',
      two: 'يوما قراءة هذا العام',
      one: 'يوم قراءة واحد هذا العام',
      zero: 'لا أيام قراءة هذا العام بعد',
    );
    return '$_temp0';
  }

  @override
  String get pagesThisMonth => 'صفحات هذا الشهر';

  @override
  String get daysThisYear => 'أيام القراءة هذا العام';

  @override
  String dayPages(String day, String pages) {
    return '$day: $pages';
  }

  @override
  String get lastSevenDays => 'آخر 7 أيام';

  @override
  String get chartLess => 'أقل';

  @override
  String get chartMore => 'أكثر';

  @override
  String semReadingGrid(int weeks, String days) {
    return 'مخطط القراءة، آخر $weeks أسبوعًا: $days.';
  }

  @override
  String daysWithReading(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count يوم قراءة',
      many: '$count يوم قراءة',
      few: '$count أيام قراءة',
      two: 'يوما قراءة',
      one: 'يوم قراءة واحد',
      zero: 'لا يوم قراءة',
    );
    return '$_temp0';
  }

  @override
  String get consistencyHadith => '«أحبُّ الأعمالِ إلى اللهِ أدومُها وإن قلَّ»';

  @override
  String get consistencyHadithSource => 'متفق عليه';

  @override
  String get dailyReminder => 'تذكير يومي';

  @override
  String dailyReminderDetail(String time) {
    return 'حوالي $time، في الأيام التي لم تقرأ فيها بعد';
  }

  @override
  String get dailyReminderOff => 'إشعار في الأيام التي لم تقرأ فيها بعد';

  @override
  String get reminderTime => 'وقت التذكير';

  @override
  String get reminderOfferTitle => 'تذكير كل يوم؟';

  @override
  String get reminderOfferBody =>
      'يستطيع رفيق أن يذكّرك كل يوم في الوقت الذي تختاره، ولا يذكّرك في الأيام التي قرأت فيها.';

  @override
  String reminderOfferAt(String time) {
    return 'ذكّرني عند $time';
  }

  @override
  String get reminderOtherTime => 'وقت آخر';

  @override
  String reminderSet(String time) {
    return 'ضُبط التذكير عند $time';
  }

  @override
  String get reminderBlocked => 'الإشعارات متوقفة لرفيق. يمكنك تفعيلها من إعدادات الهاتف.';

  @override
  String get reminderChannel => 'تذكير القراءة اليومية';

  @override
  String get reminderTitle => 'وِردك اليومي';

  @override
  String reminderBody(String surah, int page) {
    return 'تابع من $surah، الصفحة $page.';
  }

  @override
  String reminderBodyTarget(String pages, String surah, int page) {
    return '$pages اليوم. تابع من $surah، الصفحة $page.';
  }

  @override
  String goalKhatmToday(String pages) {
    return 'الختمة اليوم: $pages';
  }

  @override
  String get backToNotes => 'العودة إلى الملاحظات';

  @override
  String get backToBookmarks => 'العودة إلى العلامات';

  @override
  String get backToSurahs => 'العودة إلى السور';

  @override
  String get backToKhatm => 'العودة إلى الختمة';

  @override
  String get backToSearch => 'العودة إلى البحث';
}
