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

  @override
  String get layout => 'Layout';

  @override
  String get layoutExplanation =>
      'Scroll reads the Quran as one continuous text. Pages turn the 604 pages of the Madinah mushaf.';

  @override
  String get layoutScroll => 'Scroll';

  @override
  String get layoutPages => 'Pages';

  @override
  String get tooltipPageView => 'Read page by page';

  @override
  String get tooltipScrollView => 'Read as one scroll';

  @override
  String get share => 'Share';

  @override
  String get shareAyah => 'Share the ayah';

  @override
  String get shareAsImage => 'Share as an image';

  @override
  String get shareAsText => 'Share as text';

  @override
  String get shareFailed => 'Could not share. Try again.';

  @override
  String get dailyGoal => 'Daily reading goal';

  @override
  String get dailyGoalExplanation =>
      'A page counts once it has stayed on screen long enough to read, and you confirm it after reading. 20 pages a day is a juz: the whole Quran in a month.';

  @override
  String get dailyGoalOff => 'Off';

  @override
  String pagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '1 page',
    );
    return '$_temp0';
  }

  @override
  String todayProgress(int read, int goal) {
    return 'Today $read/$goal';
  }

  @override
  String semTodayProgress(int read, int goal) {
    return '$read of $goal pages read today';
  }

  @override
  String khatmProgress(int page, int total, int percent) {
    return 'Page $page of $total · $percent%';
  }

  @override
  String get navRead => 'Read';

  @override
  String get navSurahs => 'Surahs';

  @override
  String get navBookmarks => 'Bookmarks';

  @override
  String get navMore => 'More';

  @override
  String get continueReading => 'Continue reading';

  @override
  String bookmarksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bookmarks',
      one: '1 bookmark',
      zero: 'Bookmarks',
    );
    return '$_temp0';
  }

  @override
  String get sortBookmarks => 'Sort bookmarks';

  @override
  String get sortNewest => 'Newest first';

  @override
  String get sortQuranOrder => 'In Quran order';

  @override
  String get noBookmarksHint => 'No bookmarks yet. While reading, press and hold an ayah to bookmark it.';

  @override
  String get scrubberLabel => 'Go through the Quran';

  @override
  String get tooltipOpenSurahs => 'Surahs, juz and pages';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String get soon => 'Soon';

  @override
  String get soonRecitation => 'Recitation audio';

  @override
  String get soonRecitationDetail => 'Listen to an ayah, a page or a surah';

  @override
  String get soonOffline => 'Taraweeh without a computer';

  @override
  String get soonOfflineDetail => 'Recognition on the phone itself';

  @override
  String get listen => 'Listen';

  @override
  String get translation => 'Translation';

  @override
  String get tafsir => 'Tafsir';

  @override
  String get khatmPlanner => 'Khatm planner';

  @override
  String get khatmPlannerDetail => 'Plan a complete reading and follow it day by day';

  @override
  String get khatmExplanation =>
      'Read the whole Quran by a date you choose. Today’s target adapts as you go: read ahead and the days after ask less.';

  @override
  String get khatmFinishIn => 'Finish in';

  @override
  String khatmDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String get khatmJuzADay => 'A juz a day';

  @override
  String get khatmPickDate => 'Pick a date';

  @override
  String get khatmLastDay => 'Last day of the khatm';

  @override
  String get khatmStartAt => 'Start';

  @override
  String get khatmFromHere => 'Where I am reading';

  @override
  String get khatmFromBeginning => 'From the beginning';

  @override
  String khatmPreview(int pages, String date) {
    String _temp0 = intl.Intl.pluralLogic(
      pages,
      locale: localeName,
      other: 'About $pages pages a day',
      one: 'About 1 page a day',
    );
    return '$_temp0 · ends $date';
  }

  @override
  String get khatmStart => 'Start khatm';

  @override
  String khatmPagesRead(int read) {
    return '$read of 604 pages read';
  }

  @override
  String khatmToday(int read, int target) {
    return 'Today: $read of $target pages';
  }

  @override
  String khatmDaysLeft(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days left',
      one: 'Last day',
    );
    return '$_temp0';
  }

  @override
  String khatmEnds(String date) {
    return 'ends $date';
  }

  @override
  String get khatmPastEnd => 'Past the planned end';

  @override
  String khatmPagesLeft(int pages) {
    String _temp0 = intl.Intl.pluralLogic(
      pages,
      locale: localeName,
      other: '$pages pages left',
      one: '1 page left',
    );
    return '$_temp0';
  }

  @override
  String khatmContinue(int page) {
    return 'Continue khatm (page $page)';
  }

  @override
  String get khatmChangeEnd => 'Change end date';

  @override
  String get khatmStop => 'Stop this khatm';

  @override
  String get khatmStopTitle => 'Stop this khatm?';

  @override
  String get khatmStopBody =>
      'The pages read in this plan will be forgotten. Your reading log and finished khatms are kept.';

  @override
  String get khatmStopConfirm => 'Stop';

  @override
  String get khatmSaveFailed => 'Could not save the khatm plan. Try again.';

  @override
  String get khatmFinished => 'Finished khatms';

  @override
  String khatmCompletedOn(String date) {
    return 'Completed $date';
  }

  @override
  String khatmInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'in $days days',
      one: 'in 1 day',
    );
    return '$_temp0';
  }

  @override
  String get khatmComplete => 'Khatm complete';

  @override
  String get khatmSection => 'Khatm';

  @override
  String khatmCard(int read) {
    return '$read of 604 pages';
  }

  @override
  String semKhatmToday(int read, int target) {
    return 'Khatm: $read of $target pages read today';
  }

  @override
  String get addNote => 'Add a note';

  @override
  String get editNote => 'Edit note';

  @override
  String noteOn(String reference) {
    return 'Note on $reference';
  }

  @override
  String get noteHint => 'Write your note';

  @override
  String get saveNote => 'Save';

  @override
  String get deleteNote => 'Delete note';

  @override
  String get noteSaved => 'Note saved';

  @override
  String get noteDeleted => 'Note deleted';

  @override
  String get noteSaveFailed => 'Could not save the note. Your text is still here.';

  @override
  String get noteDeleteFailed => 'Could not delete the note.';

  @override
  String get notes => 'Notes';

  @override
  String get semNote => 'note';

  @override
  String notesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notes',
      one: '1 note',
      zero: 'Notes',
    );
    return '$_temp0';
  }

  @override
  String get noNotesHint => 'Tap an ayah, then Add a note. Your notes appear here.';

  @override
  String get reviewTitle => 'Count this reading?';

  @override
  String get reviewExplanation => 'These pages stayed on screen long enough to read. Untick any you did not read.';

  @override
  String reviewCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Count $count pages',
      one: 'Count 1 page',
      zero: 'Count nothing',
    );
    return '$_temp0';
  }

  @override
  String get reviewNotNow => 'Not now';

  @override
  String get reviewDiscard => 'Don’t count these';

  @override
  String reviewCounted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages counted',
      one: '1 page counted',
    );
    return '$_temp0';
  }

  @override
  String get reviewFailed => 'Could not save your reading. It is still waiting; try again.';

  @override
  String reviewWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages waiting to be counted',
      one: '1 page waiting to be counted',
    );
    return '$_temp0';
  }

  @override
  String get reviewAction => 'Review';

  @override
  String get khatmMap => 'Pages read';

  @override
  String get khatmMapHint =>
      'Tap a juz to mark its pages read or unread: to fix a mistake, or to add reading from a paper mushaf.';

  @override
  String semJuzTile(int juz, int read, int total) {
    return 'Juz $juz, $read of $total pages read';
  }

  @override
  String khatmJuzPages(int first, int last, int read, int total) {
    return 'Pages $first–$last · $read of $total read';
  }

  @override
  String get khatmMarkAllRead => 'Mark all read';

  @override
  String get khatmMarkAllUnread => 'Mark all unread';

  @override
  String get translationAndTafsir => 'Translation and tafsir';

  @override
  String get translationAndTafsirDetail => 'The meaning of each ayah, from trusted publishers';

  @override
  String get chooseTranslation => 'Choose a translation';

  @override
  String get chooseTafsir => 'Choose a tafsir';

  @override
  String get chooseTextExplanation => 'Each text is shown exactly as its publisher issued it.';

  @override
  String get chooseText => 'Choose the text';

  @override
  String get textLanguageEn => 'English';

  @override
  String get textLanguageFr => 'French';

  @override
  String get textLanguageAr => 'Arabic';

  @override
  String inLanguage(String language) {
    return 'In $language';
  }

  @override
  String textSourceLine(String credit, String version) {
    return '$credit · version $version · QuranEnc.com';
  }

  @override
  String get translationNote => 'A translation conveys the meanings of the Quran; it is not the Quran itself.';

  @override
  String get footnotes => 'Footnotes';

  @override
  String get previousAyah => 'Previous ayah';

  @override
  String get nextAyah => 'Next ayah';

  @override
  String get textLoadFailed => 'This text could not be opened. Reinstalling Rafiq should fix it.';

  @override
  String get listenComingSoon => 'Listening to the recitation is coming soon.';

  @override
  String get yourReading => 'Your reading';

  @override
  String readingRun(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days in a row',
      one: '1 day in a row',
    );
    return '$_temp0';
  }

  @override
  String get readingRunNone => 'Read a page today to start.';

  @override
  String readingBestRun(String days) {
    return 'Best: $days';
  }

  @override
  String daysCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String daysReadThisYear(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days read this year',
      one: '1 day read this year',
      zero: 'No days read yet this year',
    );
    return '$_temp0';
  }

  @override
  String get pagesThisMonth => 'Pages this month';

  @override
  String get daysThisYear => 'Days read this year';

  @override
  String dayPages(String day, String pages) {
    return '$day: $pages';
  }

  @override
  String get lastSevenDays => 'Last 7 days';

  @override
  String get chartLess => 'Less';

  @override
  String get chartMore => 'More';

  @override
  String semReadingGrid(int weeks, String days) {
    return 'Reading chart, the last $weeks weeks: $days.';
  }

  @override
  String daysWithReading(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days read',
      one: '1 day read',
      zero: 'no day read',
    );
    return '$_temp0';
  }

  @override
  String get consistencyHadith => '“The most beloved deeds to Allah are the most consistent, even if they are small.”';

  @override
  String get consistencyHadithSource => 'Al-Bukhari and Muslim';

  @override
  String get dailyReminder => 'Daily reminder';

  @override
  String dailyReminderDetail(String time) {
    return 'Around $time, on days you haven’t read yet';
  }

  @override
  String get dailyReminderOff => 'A notification on days you haven’t read yet';

  @override
  String get reminderTime => 'Reminder time';

  @override
  String get reminderOfferTitle => 'A daily reminder?';

  @override
  String get reminderOfferBody =>
      'Rafiq can remind you each day at a time you choose. On days you have already read, it stays quiet.';

  @override
  String reminderOfferAt(String time) {
    return 'Remind me at $time';
  }

  @override
  String get reminderOtherTime => 'Another time';

  @override
  String reminderSet(String time) {
    return 'Reminder set for $time';
  }

  @override
  String get reminderBlocked => 'Notifications are off for Rafiq. You can turn them on in the phone’s settings.';

  @override
  String get reminderChannel => 'Daily reading reminder';

  @override
  String get reminderTitle => 'Your daily reading';

  @override
  String reminderBody(String surah, int page) {
    return 'Continue at $surah, page $page.';
  }

  @override
  String reminderBodyTarget(String pages, String surah, int page) {
    return '$pages today. Continue at $surah, page $page.';
  }

  @override
  String goalKhatmToday(String pages) {
    return 'Khatm today: $pages';
  }

  @override
  String get backToNotes => 'Back to notes';

  @override
  String get backToBookmarks => 'Back to bookmarks';

  @override
  String get backToSurahs => 'Back to surahs';

  @override
  String get backToKhatm => 'Back to the khatm';

  @override
  String get backToSearch => 'Back to search';

  @override
  String get adhkar => 'Adhkar';

  @override
  String get adhkarDetail => 'Morning, evening, after prayer, before sleep';

  @override
  String adhkarNowDetail(String collection) {
    return 'Now: $collection';
  }

  @override
  String get adhkarMorning => 'Morning adhkar';

  @override
  String get adhkarEvening => 'Evening adhkar';

  @override
  String get adhkarPrayer => 'After prayer';

  @override
  String get adhkarSleep => 'Before sleep';

  @override
  String get adhkarAnytime => 'Any time';

  @override
  String get adhkarMorningWhen => 'After Fajr';

  @override
  String get adhkarEveningWhen => 'After Asr';

  @override
  String get adhkarPrayerWhen => 'After each obligatory prayer';

  @override
  String get adhkarSleepWhen => 'In bed, before sleeping';

  @override
  String get adhkarAnytimeWhen => 'Short adhkar for the whole day';

  @override
  String get adhkarNow => 'Now';

  @override
  String adhkarProgress(int done, int total) {
    return '$done of $total today';
  }

  @override
  String get adhkarDoneToday => 'Done today';

  @override
  String get adhkarTapToCount => 'Tap a dhikr each time you say it.';

  @override
  String get adhkarStartAgain => 'Start again';

  @override
  String get adhkarStartedAgain => 'Started again';

  @override
  String get adhkarAllDone => 'All done. May Allah accept it from you.';

  @override
  String adhkarSources(String first, String second) {
    return '$first and $second';
  }

  @override
  String semDhikrCount(int said, int count) {
    return '$said of $count';
  }

  @override
  String get semDhikrDone => 'Done';

  @override
  String get hintDhikrCount => 'count';

  @override
  String get dhikrReminders => 'Dhikr reminders';

  @override
  String get dhikrRemindersOff => 'A short dhikr at the top of the screen now and then, even when Rafiq is closed';

  @override
  String dhikrRemindersDetail(String every, String from, String to) {
    return '$every, from $from to $to';
  }

  @override
  String dhikrEvery(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: 'Every $hours hours',
      one: 'Every hour',
    );
    return '$_temp0';
  }

  @override
  String get dhikrHowOften => 'How often';

  @override
  String dhikrHowOftenExplanation(String from, String to) {
    return 'A short dhikr appears at the top of the screen, without sound, for 8 seconds, between $from and $to. Tap it to open the adhkar, or swipe it away. Android may move it by a few minutes to save battery.';
  }

  @override
  String get dhikrRemindersSet => 'Dhikr reminders on';

  @override
  String get dhikrNotificationTitle => 'Remember Allah';
}
