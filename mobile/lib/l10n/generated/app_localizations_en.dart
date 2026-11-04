// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Rafiq';

  @override
  String get needsYourAction => 'Needs your action';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get undo => 'Undo';

  @override
  String get clear => 'Clear';

  @override
  String get settings => 'Settings';

  @override
  String get statusReady => 'Ready to follow';

  @override
  String get statusStopped => 'Not following';

  @override
  String get statusConnecting => 'Connecting…';

  @override
  String get statusListening => 'Listening for the imam';

  @override
  String get statusFollowing => 'Following the imam';

  @override
  String get statusFatiha => 'Al-Fatiha';

  @override
  String get statusNoNewMatch => 'No new match yet';

  @override
  String get statusLittleSound => 'Little sound';

  @override
  String get statusNotSure => 'Not sure';

  @override
  String get statusNotMatching => 'Not matching the Quran';

  @override
  String get statusReconnecting => 'Reconnecting…';

  @override
  String get statusStopping => 'Stopping…';

  @override
  String get captionReady => 'Start following when the imam begins. No setup needed.';

  @override
  String get captionStopped => 'Showing the last position.';

  @override
  String get captionConnecting => 'The first time, the recognition server loads its speech model.';

  @override
  String get captionListening => 'The ayah appears after a few words.';

  @override
  String get captionNoNewMatch => 'Sound is coming in, but nothing new has matched the Quran for over 10 seconds.';

  @override
  String get captionLittleSound => 'The microphone has picked up very little for over 10 seconds.';

  @override
  String captionStillShowing(int ayah) {
    return 'Still showing ayah $ayah.';
  }

  @override
  String captionStillShowingConfirmed(int ayah) {
    return 'Still showing ayah $ayah, the last confirmed ayah.';
  }

  @override
  String get captionNotSure => 'Holding the last sure ayah.';

  @override
  String get captionNotMatching =>
      'Holding the last sure ayah. This happens during duʿāʾ or when the words aren\'t clear.';

  @override
  String get captionReconnecting => 'The microphone keeps listening meanwhile.';

  @override
  String repeatedText(String refs) {
    return 'Repeated text — could also be $refs';
  }

  @override
  String get overlineAyah => 'AYAH';

  @override
  String get overlineLastSure => 'LAST SURE';

  @override
  String get semNoPosition => 'No position yet';

  @override
  String semSurahAyah(String surah, int ayah) {
    return 'Surah $surah, ayah $ayah';
  }

  @override
  String semSurahAyahNotSure(String surah, int ayah) {
    return 'Surah $surah, ayah $ayah, not sure';
  }

  @override
  String get hintOpenSurahList => 'open the surah list';

  @override
  String get tooltipSurahs => 'Surahs';

  @override
  String juzNumber(int juz) {
    return 'Juz $juz';
  }

  @override
  String pageNumber(int page) {
    return 'Page $page';
  }

  @override
  String juzPage(int juz, int page) {
    return 'Juz $juz · Page $page';
  }

  @override
  String hizbStart(int hizb) {
    return 'Hizb $hizb';
  }

  @override
  String hizbQuarter(int hizb) {
    return '¼ Hizb $hizb';
  }

  @override
  String hizbHalf(int hizb) {
    return '½ Hizb $hizb';
  }

  @override
  String hizbThreeQuarters(int hizb) {
    return '¾ Hizb $hizb';
  }

  @override
  String ayahCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ayahs',
      one: '1 ayah',
    );
    return '$_temp0';
  }

  @override
  String surahHeaderMeta(String name, int number, String ayahs) {
    return '$name · $number · $ayahs';
  }

  @override
  String semSurahHeader(String name, int number) {
    return 'Surah $name, $number';
  }

  @override
  String get tooltipStayOnSurah => 'Stay on this surah';

  @override
  String tooltipLocked(String scope) {
    return 'Locked to $scope. Tap to unlock.';
  }

  @override
  String get tooltipTonight => 'Tonight\'s starting point';

  @override
  String get tooltipBackToReading => 'Back to reading';

  @override
  String get tooltipRemoveHint => 'Remove hint';

  @override
  String hintTonightSurah(String surah) {
    return 'Tonight: $surah';
  }

  @override
  String hintTonightJuz(int juz) {
    return 'Tonight: Juz $juz';
  }

  @override
  String lastNightEnded(String place) {
    return 'Last night ended at $place.';
  }

  @override
  String get noticePausedTitle => 'Following paused';

  @override
  String get noticePausedBody => 'The app went to the background. The last position stays on screen.';

  @override
  String get actionResume => 'Resume';

  @override
  String get actionTryAgain => 'Try again';

  @override
  String get noticeMicPermissionTitle => 'Rafiq needs the microphone';

  @override
  String get noticeMicPermissionBody =>
      'It listens to the imam\'s recitation to find the ayah. If you denied it before, allow it in your phone settings: Apps → Rafiq → Permissions → Microphone.';

  @override
  String get noticeMicStoppedTitle => 'The microphone stopped working';

  @override
  String get noticeMicStoppedBody =>
      'Rafiq could not use the microphone. Check that no other app is recording, then try again.';

  @override
  String get noticeUnreachableTitle => 'Can\'t reach the recognition server';

  @override
  String get noticeUnreachableBody =>
      'This build recognises on a computer on the same Wi-Fi. Check that it\'s running and that the address in Settings is right.';

  @override
  String get actionTestConnection => 'Test connection';

  @override
  String get noticeServerStoppedTitle => 'Recognition stopped';

  @override
  String get emptyListening => 'Keep the phone where it can hear the imam.';

  @override
  String get emptyIdle => 'Rafiq listens to the imam and shows the surah and ayah, live.';

  @override
  String get browseSurahs => 'Browse surahs';

  @override
  String get controlPreparing => 'Preparing…';

  @override
  String get controlFinishing => 'Finishing the last words…';

  @override
  String get controlStop => 'Stop following';

  @override
  String get controlStart => 'Start following';

  @override
  String get semStartFollowing => 'Start following the imam';

  @override
  String get hearingSound => 'Hearing sound';

  @override
  String get veryLittleSound => 'Very little sound';

  @override
  String get backToImam => 'Back to the imam';

  @override
  String backToImamAt(String ref) {
    return 'Back to the imam · $ref';
  }

  @override
  String ayahSheetTitle(String surah, int ayah) {
    return '$surah · ayah $ayah';
  }

  @override
  String get imamJumpExplanation => 'Rafiq jumps to this ayah and keeps following from it.';

  @override
  String get startFirstExplanation => 'Start following first, then tap the ayah the imam is on.';

  @override
  String get imamIsHere => 'The imam is here';

  @override
  String get unlockAll => 'Unlock: search the whole Quran again';

  @override
  String stayOnSurah(String surah) {
    return 'Stay on $surah';
  }

  @override
  String get stayOnThisSurah => 'Stay on this surah';

  @override
  String get lockExplanation =>
      'Rafiq will not look in other surahs until you unlock. Al-Fatiha is still recognised at each rakʿah.';

  @override
  String get hintSheetTitle => 'Tonight\'s starting point';

  @override
  String get hintSheetExplanation =>
      'Optional. Rafiq finds the imam without it; a hint only makes the first ayah appear sooner.';

  @override
  String get hintSheetRestarts => 'Changing it restarts listening.';

  @override
  String get hintNone => 'None';

  @override
  String get hintSurah => 'Surah';

  @override
  String get hintJuz => 'Juz';

  @override
  String get hintNoneExplanation => 'No hint: Rafiq searches the whole Quran.';

  @override
  String get searchByNameOrNumber => 'Search by name or number';

  @override
  String get introTitle => 'Taraweeh mode';

  @override
  String get introLead => 'Rafiq listens to the imam and shows the ayah being recited, live.';

  @override
  String get introMic => 'It uses the microphone only while following. The screen stays on.';

  @override
  String get introServer =>
      'This test build recognises on a computer on the same Wi-Fi (Settings → Recognition server).';

  @override
  String get introHafs => 'It follows recitation in Ḥafṣ ʿan ʿĀṣim only.';

  @override
  String get introCorrect =>
      'If it is ever wrong, tap the ayah the imam is on. When unsure, it says so rather than guess.';

  @override
  String get notNow => 'Not now';

  @override
  String semAyah(int ayah) {
    return 'Ayah $ayah';
  }

  @override
  String semAyahImamHere(int ayah) {
    return 'Ayah $ayah, the imam is here';
  }

  @override
  String get hintMarkImam => 'mark where the imam is';

  @override
  String get hintAyahActions => 'ayah actions';

  @override
  String get tooltipNavigate => 'Surahs, juz and bookmarks';

  @override
  String get tooltipSearch => 'Search the Quran';

  @override
  String semReaderBar(String surah, int ayah, int juz, int page) {
    return '$surah, ayah $ayah. Juz $juz, page $page. Open the index';
  }

  @override
  String get taraweeh => 'Taraweeh';

  @override
  String get semTaraweehEntry => 'Taraweeh: follow the imam';

  @override
  String get bookmark => 'Bookmark';

  @override
  String get removeBookmark => 'Remove bookmark';

  @override
  String get copyAyah => 'Copy the ayah';

  @override
  String bookmarked(String ref) {
    return 'Bookmarked $ref';
  }

  @override
  String get bookmarkFailed => 'Could not save the bookmark. Try again.';

  @override
  String get bookmarkRemoved => 'Bookmark removed';

  @override
  String get bookmarkRemoveFailed => 'Could not remove the bookmark. Try again.';

  @override
  String copied(String ref) {
    return 'Copied $ref';
  }

  @override
  String get goTo => 'Go to';

  @override
  String get tabSurahs => 'Surahs';

  @override
  String get tabJuz => 'Juz';

  @override
  String get tabPages => 'Pages';

  @override
  String get tabBookmarks => 'Bookmarks';

  @override
  String fromPlacePage(String place, int page) {
    return 'From $place · Page $page';
  }

  @override
  String fromPlaceJuz(String place, int juz) {
    return 'From $place · Juz $juz';
  }

  @override
  String get whereTaraweehEnded => 'Where Taraweeh ended';

  @override
  String get today => 'today';

  @override
  String get yesterday => 'yesterday';

  @override
  String daysAgo(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String get noBookmarks => 'No bookmarks yet. Tap an ayah while reading to bookmark it.';

  @override
  String get searchHint => 'Surah, 2:255, page 50, or Arabic words';

  @override
  String searchFirstOf(int shown, int total) {
    return 'First $shown of $total ayahs';
  }

  @override
  String searchTooShort(int count) {
    return 'Type at least $count letters to search the text.';
  }

  @override
  String searchNothing(String query) {
    return 'Nothing found for “$query”.';
  }

  @override
  String get searchBy => 'Search by';

  @override
  String get searchHelpSurah => 'A surah: Al-Kahf, الكهف, or 18';

  @override
  String get searchHelpAyah => 'An ayah: 2:255';

  @override
  String get searchHelpPlace => 'A page or juz: page 50, juz 30';

  @override
  String get searchHelpWords => 'Words of the Quran, in Arabic: ٱلْحَمْدُ لِلَّهِ (with or without tashkeel)';

  @override
  String surahNumberAyahs(int number, String ayahs) {
    return 'Surah $number · $ayahs';
  }

  @override
  String get groupReading => 'Reading';

  @override
  String get quranTextSize => 'Quran text size';

  @override
  String get appearance => 'Appearance';

  @override
  String get appearanceExplanation => 'The reader follows your phone. Taraweeh mode has its own setting below.';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeLight => 'Light';

  @override
  String get themeSystem => 'System';

  @override
  String get language => 'Language';

  @override
  String get languageExplanation => 'Quran text is always shown as revealed, in Arabic.';

  @override
  String get languageSystem => 'System';

  @override
  String get groupTaraweeh => 'Taraweeh';

  @override
  String get darkDuringTaraweeh => 'Dark during Taraweeh';

  @override
  String get darkDuringTaraweehDetail => 'Taraweeh mode stays dark, whatever the reader uses';

  @override
  String get keepScreenOn => 'Keep screen on while following';

  @override
  String get keepScreenOnDetail => 'Recommended during prayer';

  @override
  String get groupRecitation => 'Recitation';

  @override
  String get riwaya => 'Riwāya';

  @override
  String get hafs => 'Ḥafṣ ʿan ʿĀṣim';

  @override
  String get hafsOnly =>
      'Rafiq recognises and numbers ayahs in the Ḥafṣ riwāya only. Qālūn and Warsh are not supported yet.';

  @override
  String get groupServer => 'Recognition server';

  @override
  String get serverExplanation => 'This build recognises on a computer on the same Wi-Fi; it does not work without it.';

  @override
  String get serverAddress => 'Server address';

  @override
  String get serverHelp =>
      'Start the server on the computer with:  python -m rafiq_server --host 0.0.0.0\nthen enter its Wi-Fi address and port. On the Android emulator, use 10.0.2.2:8765.';

  @override
  String get groupDeveloper => 'Developer';

  @override
  String get showDiagnostics => 'Show diagnostics';

  @override
  String get showDiagnosticsDetail => 'What the speech model hears, for testing';

  @override
  String get asrBench => 'On-device speech benchmark';

  @override
  String get asrBenchDetail => 'Can this phone recognise the imam without the computer? A test, not a feature.';

  @override
  String get groupAbout => 'About';

  @override
  String get aboutLead =>
      'Rafiq is a Quran reader that can follow the imam during Taraweeh and show the surah and ayah being recited.';

  @override
  String get textSizeSize => 'Size';

  @override
  String get textSizeNote => 'The ayah numbers and line spacing scale with the text.';

  @override
  String get healthFailed => 'Failed';

  @override
  String healthConnected(int ms, String device) {
    return 'Connected · $ms ms · speech model $device';
  }

  @override
  String get healthReadyOnFirstUse => 'ready on first use';

  @override
  String healthNoAsr(int ms) {
    return 'Connected · $ms ms · speech recognition NOT installed';
  }
}
