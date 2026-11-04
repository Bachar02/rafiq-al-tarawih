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
}
