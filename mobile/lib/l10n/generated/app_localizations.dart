import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('ar'), Locale('en'), Locale('fr')];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Rafiq'**
  String get appName;

  /// No description provided for @needsYourAction.
  ///
  /// In en, this message translates to:
  /// **'Needs your action'**
  String get needsYourAction;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @statusReady.
  ///
  /// In en, this message translates to:
  /// **'Ready to follow'**
  String get statusReady;

  /// No description provided for @statusStopped.
  ///
  /// In en, this message translates to:
  /// **'Not following'**
  String get statusStopped;

  /// No description provided for @statusConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get statusConnecting;

  /// No description provided for @statusListening.
  ///
  /// In en, this message translates to:
  /// **'Listening for the imam'**
  String get statusListening;

  /// No description provided for @statusFollowing.
  ///
  /// In en, this message translates to:
  /// **'Following the imam'**
  String get statusFollowing;

  /// No description provided for @statusFatiha.
  ///
  /// In en, this message translates to:
  /// **'Al-Fatiha'**
  String get statusFatiha;

  /// No description provided for @statusNoNewMatch.
  ///
  /// In en, this message translates to:
  /// **'No new match yet'**
  String get statusNoNewMatch;

  /// No description provided for @statusLittleSound.
  ///
  /// In en, this message translates to:
  /// **'Little sound'**
  String get statusLittleSound;

  /// No description provided for @statusNotSure.
  ///
  /// In en, this message translates to:
  /// **'Not sure'**
  String get statusNotSure;

  /// No description provided for @statusNotMatching.
  ///
  /// In en, this message translates to:
  /// **'Not matching the Quran'**
  String get statusNotMatching;

  /// No description provided for @statusReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get statusReconnecting;

  /// No description provided for @statusStopping.
  ///
  /// In en, this message translates to:
  /// **'Stopping…'**
  String get statusStopping;

  /// No description provided for @captionReady.
  ///
  /// In en, this message translates to:
  /// **'Start following when the imam begins. No setup needed.'**
  String get captionReady;

  /// No description provided for @captionStopped.
  ///
  /// In en, this message translates to:
  /// **'Showing the last position.'**
  String get captionStopped;

  /// No description provided for @captionConnecting.
  ///
  /// In en, this message translates to:
  /// **'The first time, the recognition server loads its speech model.'**
  String get captionConnecting;

  /// No description provided for @captionListening.
  ///
  /// In en, this message translates to:
  /// **'The ayah appears after a few words.'**
  String get captionListening;

  /// No description provided for @captionNoNewMatch.
  ///
  /// In en, this message translates to:
  /// **'Sound is coming in, but nothing new has matched the Quran for over 10 seconds.'**
  String get captionNoNewMatch;

  /// No description provided for @captionLittleSound.
  ///
  /// In en, this message translates to:
  /// **'The microphone has picked up very little for over 10 seconds.'**
  String get captionLittleSound;

  /// No description provided for @captionStillShowing.
  ///
  /// In en, this message translates to:
  /// **'Still showing ayah {ayah}.'**
  String captionStillShowing(int ayah);

  /// No description provided for @captionStillShowingConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Still showing ayah {ayah}, the last confirmed ayah.'**
  String captionStillShowingConfirmed(int ayah);

  /// No description provided for @captionNotSure.
  ///
  /// In en, this message translates to:
  /// **'Holding the last sure ayah.'**
  String get captionNotSure;

  /// No description provided for @captionNotMatching.
  ///
  /// In en, this message translates to:
  /// **'Holding the last sure ayah. This happens during duʿāʾ or when the words aren\'t clear.'**
  String get captionNotMatching;

  /// No description provided for @captionReconnecting.
  ///
  /// In en, this message translates to:
  /// **'The microphone keeps listening meanwhile.'**
  String get captionReconnecting;

  /// No description provided for @repeatedText.
  ///
  /// In en, this message translates to:
  /// **'Repeated text — could also be {refs}'**
  String repeatedText(String refs);

  /// No description provided for @overlineAyah.
  ///
  /// In en, this message translates to:
  /// **'AYAH'**
  String get overlineAyah;

  /// No description provided for @overlineLastSure.
  ///
  /// In en, this message translates to:
  /// **'LAST SURE'**
  String get overlineLastSure;

  /// No description provided for @semNoPosition.
  ///
  /// In en, this message translates to:
  /// **'No position yet'**
  String get semNoPosition;

  /// No description provided for @semSurahAyah.
  ///
  /// In en, this message translates to:
  /// **'Surah {surah}, ayah {ayah}'**
  String semSurahAyah(String surah, int ayah);

  /// No description provided for @semSurahAyahNotSure.
  ///
  /// In en, this message translates to:
  /// **'Surah {surah}, ayah {ayah}, not sure'**
  String semSurahAyahNotSure(String surah, int ayah);

  /// No description provided for @hintOpenSurahList.
  ///
  /// In en, this message translates to:
  /// **'open the surah list'**
  String get hintOpenSurahList;

  /// No description provided for @tooltipSurahs.
  ///
  /// In en, this message translates to:
  /// **'Surahs'**
  String get tooltipSurahs;

  /// No description provided for @juzNumber.
  ///
  /// In en, this message translates to:
  /// **'Juz {juz}'**
  String juzNumber(int juz);

  /// No description provided for @pageNumber.
  ///
  /// In en, this message translates to:
  /// **'Page {page}'**
  String pageNumber(int page);

  /// No description provided for @juzPage.
  ///
  /// In en, this message translates to:
  /// **'Juz {juz} · Page {page}'**
  String juzPage(int juz, int page);

  /// No description provided for @hizbStart.
  ///
  /// In en, this message translates to:
  /// **'Hizb {hizb}'**
  String hizbStart(int hizb);

  /// No description provided for @hizbQuarter.
  ///
  /// In en, this message translates to:
  /// **'¼ Hizb {hizb}'**
  String hizbQuarter(int hizb);

  /// No description provided for @hizbHalf.
  ///
  /// In en, this message translates to:
  /// **'½ Hizb {hizb}'**
  String hizbHalf(int hizb);

  /// No description provided for @hizbThreeQuarters.
  ///
  /// In en, this message translates to:
  /// **'¾ Hizb {hizb}'**
  String hizbThreeQuarters(int hizb);

  /// No description provided for @ayahCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 ayah} other{{count} ayahs}}'**
  String ayahCount(int count);

  /// No description provided for @surahHeaderMeta.
  ///
  /// In en, this message translates to:
  /// **'{name} · {number} · {ayahs}'**
  String surahHeaderMeta(String name, int number, String ayahs);

  /// No description provided for @semSurahHeader.
  ///
  /// In en, this message translates to:
  /// **'Surah {name}, {number}'**
  String semSurahHeader(String name, int number);

  /// No description provided for @tooltipStayOnSurah.
  ///
  /// In en, this message translates to:
  /// **'Stay on this surah'**
  String get tooltipStayOnSurah;

  /// No description provided for @tooltipLocked.
  ///
  /// In en, this message translates to:
  /// **'Locked to {scope}. Tap to unlock.'**
  String tooltipLocked(String scope);

  /// No description provided for @tooltipTonight.
  ///
  /// In en, this message translates to:
  /// **'Tonight\'s starting point'**
  String get tooltipTonight;

  /// No description provided for @tooltipBackToReading.
  ///
  /// In en, this message translates to:
  /// **'Back to reading'**
  String get tooltipBackToReading;

  /// No description provided for @tooltipRemoveHint.
  ///
  /// In en, this message translates to:
  /// **'Remove hint'**
  String get tooltipRemoveHint;

  /// No description provided for @hintTonightSurah.
  ///
  /// In en, this message translates to:
  /// **'Tonight: {surah}'**
  String hintTonightSurah(String surah);

  /// No description provided for @hintTonightJuz.
  ///
  /// In en, this message translates to:
  /// **'Tonight: Juz {juz}'**
  String hintTonightJuz(int juz);

  /// No description provided for @lastNightEnded.
  ///
  /// In en, this message translates to:
  /// **'Last night ended at {place}.'**
  String lastNightEnded(String place);

  /// No description provided for @noticePausedTitle.
  ///
  /// In en, this message translates to:
  /// **'Following paused'**
  String get noticePausedTitle;

  /// No description provided for @noticePausedBody.
  ///
  /// In en, this message translates to:
  /// **'The app went to the background. The last position stays on screen.'**
  String get noticePausedBody;

  /// No description provided for @actionResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get actionResume;

  /// No description provided for @actionTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get actionTryAgain;

  /// No description provided for @noticeMicPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Rafiq needs the microphone'**
  String get noticeMicPermissionTitle;

  /// No description provided for @noticeMicPermissionBody.
  ///
  /// In en, this message translates to:
  /// **'It listens to the imam\'s recitation to find the ayah. If you denied it before, allow it in your phone settings: Apps → Rafiq → Permissions → Microphone.'**
  String get noticeMicPermissionBody;

  /// No description provided for @noticeMicStoppedTitle.
  ///
  /// In en, this message translates to:
  /// **'The microphone stopped working'**
  String get noticeMicStoppedTitle;

  /// No description provided for @noticeMicStoppedBody.
  ///
  /// In en, this message translates to:
  /// **'Rafiq could not use the microphone. Check that no other app is recording, then try again.'**
  String get noticeMicStoppedBody;

  /// No description provided for @noticeUnreachableTitle.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the recognition server'**
  String get noticeUnreachableTitle;

  /// No description provided for @noticeUnreachableBody.
  ///
  /// In en, this message translates to:
  /// **'This build recognises on a computer on the same Wi-Fi. Check that it\'s running and that the address in Settings is right.'**
  String get noticeUnreachableBody;

  /// No description provided for @actionTestConnection.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get actionTestConnection;

  /// No description provided for @noticeServerStoppedTitle.
  ///
  /// In en, this message translates to:
  /// **'Recognition stopped'**
  String get noticeServerStoppedTitle;

  /// No description provided for @emptyListening.
  ///
  /// In en, this message translates to:
  /// **'Keep the phone where it can hear the imam.'**
  String get emptyListening;

  /// No description provided for @emptyIdle.
  ///
  /// In en, this message translates to:
  /// **'Rafiq listens to the imam and shows the surah and ayah, live.'**
  String get emptyIdle;

  /// No description provided for @browseSurahs.
  ///
  /// In en, this message translates to:
  /// **'Browse surahs'**
  String get browseSurahs;

  /// No description provided for @controlPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing…'**
  String get controlPreparing;

  /// No description provided for @controlFinishing.
  ///
  /// In en, this message translates to:
  /// **'Finishing the last words…'**
  String get controlFinishing;

  /// No description provided for @controlStop.
  ///
  /// In en, this message translates to:
  /// **'Stop following'**
  String get controlStop;

  /// No description provided for @controlStart.
  ///
  /// In en, this message translates to:
  /// **'Start following'**
  String get controlStart;

  /// No description provided for @semStartFollowing.
  ///
  /// In en, this message translates to:
  /// **'Start following the imam'**
  String get semStartFollowing;

  /// No description provided for @hearingSound.
  ///
  /// In en, this message translates to:
  /// **'Hearing sound'**
  String get hearingSound;

  /// No description provided for @veryLittleSound.
  ///
  /// In en, this message translates to:
  /// **'Very little sound'**
  String get veryLittleSound;

  /// No description provided for @backToImam.
  ///
  /// In en, this message translates to:
  /// **'Back to the imam'**
  String get backToImam;

  /// No description provided for @backToImamAt.
  ///
  /// In en, this message translates to:
  /// **'Back to the imam · {ref}'**
  String backToImamAt(String ref);

  /// No description provided for @ayahSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'{surah} · ayah {ayah}'**
  String ayahSheetTitle(String surah, int ayah);

  /// No description provided for @imamJumpExplanation.
  ///
  /// In en, this message translates to:
  /// **'Rafiq jumps to this ayah and keeps following from it.'**
  String get imamJumpExplanation;

  /// No description provided for @startFirstExplanation.
  ///
  /// In en, this message translates to:
  /// **'Start following first, then tap the ayah the imam is on.'**
  String get startFirstExplanation;

  /// No description provided for @imamIsHere.
  ///
  /// In en, this message translates to:
  /// **'The imam is here'**
  String get imamIsHere;

  /// No description provided for @unlockAll.
  ///
  /// In en, this message translates to:
  /// **'Unlock: search the whole Quran again'**
  String get unlockAll;

  /// No description provided for @stayOnSurah.
  ///
  /// In en, this message translates to:
  /// **'Stay on {surah}'**
  String stayOnSurah(String surah);

  /// No description provided for @stayOnThisSurah.
  ///
  /// In en, this message translates to:
  /// **'Stay on this surah'**
  String get stayOnThisSurah;

  /// No description provided for @lockExplanation.
  ///
  /// In en, this message translates to:
  /// **'Rafiq will not look in other surahs until you unlock. Al-Fatiha is still recognised at each rakʿah.'**
  String get lockExplanation;

  /// No description provided for @hintSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Tonight\'s starting point'**
  String get hintSheetTitle;

  /// No description provided for @hintSheetExplanation.
  ///
  /// In en, this message translates to:
  /// **'Optional. Rafiq finds the imam without it; a hint only makes the first ayah appear sooner.'**
  String get hintSheetExplanation;

  /// No description provided for @hintSheetRestarts.
  ///
  /// In en, this message translates to:
  /// **'Changing it restarts listening.'**
  String get hintSheetRestarts;

  /// No description provided for @hintNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get hintNone;

  /// No description provided for @hintSurah.
  ///
  /// In en, this message translates to:
  /// **'Surah'**
  String get hintSurah;

  /// No description provided for @hintJuz.
  ///
  /// In en, this message translates to:
  /// **'Juz'**
  String get hintJuz;

  /// No description provided for @hintNoneExplanation.
  ///
  /// In en, this message translates to:
  /// **'No hint: Rafiq searches the whole Quran.'**
  String get hintNoneExplanation;

  /// No description provided for @searchByNameOrNumber.
  ///
  /// In en, this message translates to:
  /// **'Search by name or number'**
  String get searchByNameOrNumber;

  /// No description provided for @introTitle.
  ///
  /// In en, this message translates to:
  /// **'Taraweeh mode'**
  String get introTitle;

  /// No description provided for @introLead.
  ///
  /// In en, this message translates to:
  /// **'Rafiq listens to the imam and shows the ayah being recited, live.'**
  String get introLead;

  /// No description provided for @introMic.
  ///
  /// In en, this message translates to:
  /// **'It uses the microphone only while following. The screen stays on.'**
  String get introMic;

  /// No description provided for @introServer.
  ///
  /// In en, this message translates to:
  /// **'This test build recognises on a computer on the same Wi-Fi (Settings → Recognition server).'**
  String get introServer;

  /// No description provided for @introHafs.
  ///
  /// In en, this message translates to:
  /// **'It follows recitation in Ḥafṣ ʿan ʿĀṣim only.'**
  String get introHafs;

  /// No description provided for @introCorrect.
  ///
  /// In en, this message translates to:
  /// **'If it is ever wrong, tap the ayah the imam is on. When unsure, it says so rather than guess.'**
  String get introCorrect;

  /// No description provided for @notNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get notNow;

  /// No description provided for @semAyah.
  ///
  /// In en, this message translates to:
  /// **'Ayah {ayah}'**
  String semAyah(int ayah);

  /// No description provided for @semAyahImamHere.
  ///
  /// In en, this message translates to:
  /// **'Ayah {ayah}, the imam is here'**
  String semAyahImamHere(int ayah);

  /// No description provided for @hintMarkImam.
  ///
  /// In en, this message translates to:
  /// **'mark where the imam is'**
  String get hintMarkImam;

  /// No description provided for @hintAyahActions.
  ///
  /// In en, this message translates to:
  /// **'ayah actions'**
  String get hintAyahActions;

  /// No description provided for @tooltipNavigate.
  ///
  /// In en, this message translates to:
  /// **'Surahs, juz and bookmarks'**
  String get tooltipNavigate;

  /// No description provided for @tooltipSearch.
  ///
  /// In en, this message translates to:
  /// **'Search the Quran'**
  String get tooltipSearch;

  /// No description provided for @semReaderBar.
  ///
  /// In en, this message translates to:
  /// **'{surah}, ayah {ayah}. Juz {juz}, page {page}. Open the index'**
  String semReaderBar(String surah, int ayah, int juz, int page);

  /// No description provided for @taraweeh.
  ///
  /// In en, this message translates to:
  /// **'Taraweeh'**
  String get taraweeh;

  /// No description provided for @semTaraweehEntry.
  ///
  /// In en, this message translates to:
  /// **'Taraweeh: follow the imam'**
  String get semTaraweehEntry;

  /// No description provided for @bookmark.
  ///
  /// In en, this message translates to:
  /// **'Bookmark'**
  String get bookmark;

  /// No description provided for @removeBookmark.
  ///
  /// In en, this message translates to:
  /// **'Remove bookmark'**
  String get removeBookmark;

  /// No description provided for @copyAyah.
  ///
  /// In en, this message translates to:
  /// **'Copy the ayah'**
  String get copyAyah;

  /// No description provided for @bookmarked.
  ///
  /// In en, this message translates to:
  /// **'Bookmarked {ref}'**
  String bookmarked(String ref);

  /// No description provided for @bookmarkFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the bookmark. Try again.'**
  String get bookmarkFailed;

  /// No description provided for @bookmarkRemoved.
  ///
  /// In en, this message translates to:
  /// **'Bookmark removed'**
  String get bookmarkRemoved;

  /// No description provided for @bookmarkRemoveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not remove the bookmark. Try again.'**
  String get bookmarkRemoveFailed;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied {ref}'**
  String copied(String ref);

  /// No description provided for @goTo.
  ///
  /// In en, this message translates to:
  /// **'Go to'**
  String get goTo;

  /// No description provided for @tabSurahs.
  ///
  /// In en, this message translates to:
  /// **'Surahs'**
  String get tabSurahs;

  /// No description provided for @tabJuz.
  ///
  /// In en, this message translates to:
  /// **'Juz'**
  String get tabJuz;

  /// No description provided for @tabPages.
  ///
  /// In en, this message translates to:
  /// **'Pages'**
  String get tabPages;

  /// No description provided for @tabBookmarks.
  ///
  /// In en, this message translates to:
  /// **'Bookmarks'**
  String get tabBookmarks;

  /// No description provided for @fromPlacePage.
  ///
  /// In en, this message translates to:
  /// **'From {place} · Page {page}'**
  String fromPlacePage(String place, int page);

  /// No description provided for @fromPlaceJuz.
  ///
  /// In en, this message translates to:
  /// **'From {place} · Juz {juz}'**
  String fromPlaceJuz(String place, int juz);

  /// No description provided for @whereTaraweehEnded.
  ///
  /// In en, this message translates to:
  /// **'Where Taraweeh ended'**
  String get whereTaraweehEnded;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'today'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'yesterday'**
  String get yesterday;

  /// No description provided for @daysAgo.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day ago} other{{days} days ago}}'**
  String daysAgo(int days);

  /// No description provided for @noBookmarks.
  ///
  /// In en, this message translates to:
  /// **'No bookmarks yet. Tap an ayah while reading to bookmark it.'**
  String get noBookmarks;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Surah, 2:255, page 50, or Arabic words'**
  String get searchHint;

  /// No description provided for @searchFirstOf.
  ///
  /// In en, this message translates to:
  /// **'First {shown} of {total} ayahs'**
  String searchFirstOf(int shown, int total);

  /// No description provided for @searchTooShort.
  ///
  /// In en, this message translates to:
  /// **'Type at least {count} letters to search the text.'**
  String searchTooShort(int count);

  /// No description provided for @searchNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing found for “{query}”.'**
  String searchNothing(String query);

  /// No description provided for @searchBy.
  ///
  /// In en, this message translates to:
  /// **'Search by'**
  String get searchBy;

  /// No description provided for @searchHelpSurah.
  ///
  /// In en, this message translates to:
  /// **'A surah: Al-Kahf, الكهف, or 18'**
  String get searchHelpSurah;

  /// No description provided for @searchHelpAyah.
  ///
  /// In en, this message translates to:
  /// **'An ayah: 2:255'**
  String get searchHelpAyah;

  /// No description provided for @searchHelpPlace.
  ///
  /// In en, this message translates to:
  /// **'A page or juz: page 50, juz 30'**
  String get searchHelpPlace;

  /// No description provided for @searchHelpWords.
  ///
  /// In en, this message translates to:
  /// **'Words of the Quran, in Arabic: ٱلْحَمْدُ لِلَّهِ (with or without tashkeel)'**
  String get searchHelpWords;

  /// No description provided for @surahNumberAyahs.
  ///
  /// In en, this message translates to:
  /// **'Surah {number} · {ayahs}'**
  String surahNumberAyahs(int number, String ayahs);

  /// No description provided for @groupReading.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get groupReading;

  /// No description provided for @quranTextSize.
  ///
  /// In en, this message translates to:
  /// **'Quran text size'**
  String get quranTextSize;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @appearanceExplanation.
  ///
  /// In en, this message translates to:
  /// **'The reader follows your phone. Taraweeh mode has its own setting below.'**
  String get appearanceExplanation;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageExplanation.
  ///
  /// In en, this message translates to:
  /// **'Quran text is always shown as revealed, in Arabic.'**
  String get languageExplanation;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// No description provided for @groupTaraweeh.
  ///
  /// In en, this message translates to:
  /// **'Taraweeh'**
  String get groupTaraweeh;

  /// No description provided for @darkDuringTaraweeh.
  ///
  /// In en, this message translates to:
  /// **'Dark during Taraweeh'**
  String get darkDuringTaraweeh;

  /// No description provided for @darkDuringTaraweehDetail.
  ///
  /// In en, this message translates to:
  /// **'Taraweeh mode stays dark, whatever the reader uses'**
  String get darkDuringTaraweehDetail;

  /// No description provided for @keepScreenOn.
  ///
  /// In en, this message translates to:
  /// **'Keep screen on while following'**
  String get keepScreenOn;

  /// No description provided for @keepScreenOnDetail.
  ///
  /// In en, this message translates to:
  /// **'Recommended during prayer'**
  String get keepScreenOnDetail;

  /// No description provided for @groupRecitation.
  ///
  /// In en, this message translates to:
  /// **'Recitation'**
  String get groupRecitation;

  /// No description provided for @riwaya.
  ///
  /// In en, this message translates to:
  /// **'Riwāya'**
  String get riwaya;

  /// No description provided for @hafs.
  ///
  /// In en, this message translates to:
  /// **'Ḥafṣ ʿan ʿĀṣim'**
  String get hafs;

  /// No description provided for @hafsOnly.
  ///
  /// In en, this message translates to:
  /// **'Rafiq recognises and numbers ayahs in the Ḥafṣ riwāya only. Qālūn and Warsh are not supported yet.'**
  String get hafsOnly;

  /// No description provided for @groupServer.
  ///
  /// In en, this message translates to:
  /// **'Recognition server'**
  String get groupServer;

  /// No description provided for @serverExplanation.
  ///
  /// In en, this message translates to:
  /// **'This build recognises on a computer on the same Wi-Fi; it does not work without it.'**
  String get serverExplanation;

  /// No description provided for @serverAddress.
  ///
  /// In en, this message translates to:
  /// **'Server address'**
  String get serverAddress;

  /// No description provided for @serverHelp.
  ///
  /// In en, this message translates to:
  /// **'Start the server on the computer with:  python -m rafiq_server --host 0.0.0.0\nthen enter its Wi-Fi address and port. On the Android emulator, use 10.0.2.2:8765.'**
  String get serverHelp;

  /// No description provided for @groupDeveloper.
  ///
  /// In en, this message translates to:
  /// **'Developer'**
  String get groupDeveloper;

  /// No description provided for @showDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Show diagnostics'**
  String get showDiagnostics;

  /// No description provided for @showDiagnosticsDetail.
  ///
  /// In en, this message translates to:
  /// **'What the speech model hears, for testing'**
  String get showDiagnosticsDetail;

  /// No description provided for @asrBench.
  ///
  /// In en, this message translates to:
  /// **'On-device speech benchmark'**
  String get asrBench;

  /// No description provided for @asrBenchDetail.
  ///
  /// In en, this message translates to:
  /// **'Can this phone recognise the imam without the computer? A test, not a feature.'**
  String get asrBenchDetail;

  /// No description provided for @groupAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get groupAbout;

  /// No description provided for @aboutLead.
  ///
  /// In en, this message translates to:
  /// **'Rafiq is a Quran reader that can follow the imam during Taraweeh and show the surah and ayah being recited.'**
  String get aboutLead;

  /// No description provided for @textSizeSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get textSizeSize;

  /// No description provided for @textSizeNote.
  ///
  /// In en, this message translates to:
  /// **'The ayah numbers and line spacing scale with the text.'**
  String get textSizeNote;

  /// No description provided for @healthFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get healthFailed;

  /// No description provided for @healthConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected · {ms} ms · speech model {device}'**
  String healthConnected(int ms, String device);

  /// No description provided for @healthReadyOnFirstUse.
  ///
  /// In en, this message translates to:
  /// **'ready on first use'**
  String get healthReadyOnFirstUse;

  /// No description provided for @healthNoAsr.
  ///
  /// In en, this message translates to:
  /// **'Connected · {ms} ms · speech recognition NOT installed'**
  String healthNoAsr(int ms);

  /// No description provided for @layout.
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get layout;

  /// No description provided for @layoutExplanation.
  ///
  /// In en, this message translates to:
  /// **'Scroll reads the Quran as one continuous text. Pages turn the 604 pages of the Madinah mushaf.'**
  String get layoutExplanation;

  /// No description provided for @layoutScroll.
  ///
  /// In en, this message translates to:
  /// **'Scroll'**
  String get layoutScroll;

  /// No description provided for @layoutPages.
  ///
  /// In en, this message translates to:
  /// **'Pages'**
  String get layoutPages;

  /// No description provided for @tooltipPageView.
  ///
  /// In en, this message translates to:
  /// **'Read page by page'**
  String get tooltipPageView;

  /// No description provided for @tooltipScrollView.
  ///
  /// In en, this message translates to:
  /// **'Read as one scroll'**
  String get tooltipScrollView;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @shareAyah.
  ///
  /// In en, this message translates to:
  /// **'Share the ayah'**
  String get shareAyah;

  /// No description provided for @shareAsImage.
  ///
  /// In en, this message translates to:
  /// **'Share as an image'**
  String get shareAsImage;

  /// No description provided for @shareAsText.
  ///
  /// In en, this message translates to:
  /// **'Share as text'**
  String get shareAsText;

  /// No description provided for @shareFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not share. Try again.'**
  String get shareFailed;

  /// No description provided for @dailyGoal.
  ///
  /// In en, this message translates to:
  /// **'Daily reading goal'**
  String get dailyGoal;

  /// No description provided for @dailyGoalExplanation.
  ///
  /// In en, this message translates to:
  /// **'A page counts once it has stayed on screen long enough to read, and you confirm it after reading. 20 pages a day is a juz: the whole Quran in a month.'**
  String get dailyGoalExplanation;

  /// No description provided for @dailyGoalOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get dailyGoalOff;

  /// No description provided for @pagesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 page} other{{count} pages}}'**
  String pagesCount(int count);

  /// No description provided for @todayProgress.
  ///
  /// In en, this message translates to:
  /// **'Today {read}/{goal}'**
  String todayProgress(int read, int goal);

  /// No description provided for @semTodayProgress.
  ///
  /// In en, this message translates to:
  /// **'{read} of {goal} pages read today'**
  String semTodayProgress(int read, int goal);

  /// No description provided for @khatmProgress.
  ///
  /// In en, this message translates to:
  /// **'Page {page} of {total} · {percent}%'**
  String khatmProgress(int page, int total, int percent);

  /// No description provided for @navRead.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get navRead;

  /// No description provided for @navSurahs.
  ///
  /// In en, this message translates to:
  /// **'Surahs'**
  String get navSurahs;

  /// No description provided for @navBookmarks.
  ///
  /// In en, this message translates to:
  /// **'Bookmarks'**
  String get navBookmarks;

  /// No description provided for @navMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get navMore;

  /// No description provided for @continueReading.
  ///
  /// In en, this message translates to:
  /// **'Continue reading'**
  String get continueReading;

  /// No description provided for @bookmarksCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Bookmarks} =1{1 bookmark} other{{count} bookmarks}}'**
  String bookmarksCount(int count);

  /// No description provided for @sortBookmarks.
  ///
  /// In en, this message translates to:
  /// **'Sort bookmarks'**
  String get sortBookmarks;

  /// No description provided for @sortNewest.
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get sortNewest;

  /// No description provided for @sortQuranOrder.
  ///
  /// In en, this message translates to:
  /// **'In Quran order'**
  String get sortQuranOrder;

  /// No description provided for @noBookmarksHint.
  ///
  /// In en, this message translates to:
  /// **'No bookmarks yet. While reading, press and hold an ayah to bookmark it.'**
  String get noBookmarksHint;

  /// No description provided for @scrubberLabel.
  ///
  /// In en, this message translates to:
  /// **'Go through the Quran'**
  String get scrubberLabel;

  /// No description provided for @tooltipOpenSurahs.
  ///
  /// In en, this message translates to:
  /// **'Surahs, juz and pages'**
  String get tooltipOpenSurahs;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoon;

  /// No description provided for @soon.
  ///
  /// In en, this message translates to:
  /// **'Soon'**
  String get soon;

  /// No description provided for @soonRecitation.
  ///
  /// In en, this message translates to:
  /// **'Recitation audio'**
  String get soonRecitation;

  /// No description provided for @soonRecitationDetail.
  ///
  /// In en, this message translates to:
  /// **'Listen to an ayah, a page or a surah'**
  String get soonRecitationDetail;

  /// No description provided for @soonOffline.
  ///
  /// In en, this message translates to:
  /// **'Taraweeh without a computer'**
  String get soonOffline;

  /// No description provided for @soonOfflineDetail.
  ///
  /// In en, this message translates to:
  /// **'Recognition on the phone itself'**
  String get soonOfflineDetail;

  /// No description provided for @listen.
  ///
  /// In en, this message translates to:
  /// **'Listen'**
  String get listen;

  /// No description provided for @translation.
  ///
  /// In en, this message translates to:
  /// **'Translation'**
  String get translation;

  /// No description provided for @tafsir.
  ///
  /// In en, this message translates to:
  /// **'Tafsir'**
  String get tafsir;

  /// No description provided for @khatmPlanner.
  ///
  /// In en, this message translates to:
  /// **'Khatm planner'**
  String get khatmPlanner;

  /// No description provided for @khatmPlannerDetail.
  ///
  /// In en, this message translates to:
  /// **'Plan a complete reading and follow it day by day'**
  String get khatmPlannerDetail;

  /// No description provided for @khatmExplanation.
  ///
  /// In en, this message translates to:
  /// **'Read the whole Quran by a date you choose. Today’s target adapts as you go: read ahead and the days after ask less.'**
  String get khatmExplanation;

  /// No description provided for @khatmFinishIn.
  ///
  /// In en, this message translates to:
  /// **'Finish in'**
  String get khatmFinishIn;

  /// No description provided for @khatmDays.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day} other{{days} days}}'**
  String khatmDays(int days);

  /// No description provided for @khatmJuzADay.
  ///
  /// In en, this message translates to:
  /// **'A juz a day'**
  String get khatmJuzADay;

  /// No description provided for @khatmPickDate.
  ///
  /// In en, this message translates to:
  /// **'Pick a date'**
  String get khatmPickDate;

  /// No description provided for @khatmLastDay.
  ///
  /// In en, this message translates to:
  /// **'Last day of the khatm'**
  String get khatmLastDay;

  /// No description provided for @khatmStartAt.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get khatmStartAt;

  /// No description provided for @khatmFromHere.
  ///
  /// In en, this message translates to:
  /// **'Where I am reading'**
  String get khatmFromHere;

  /// No description provided for @khatmFromBeginning.
  ///
  /// In en, this message translates to:
  /// **'From the beginning'**
  String get khatmFromBeginning;

  /// No description provided for @khatmPreview.
  ///
  /// In en, this message translates to:
  /// **'{pages, plural, =1{About 1 page a day} other{About {pages} pages a day}} · ends {date}'**
  String khatmPreview(int pages, String date);

  /// No description provided for @khatmStart.
  ///
  /// In en, this message translates to:
  /// **'Start khatm'**
  String get khatmStart;

  /// No description provided for @khatmPagesRead.
  ///
  /// In en, this message translates to:
  /// **'{read} of 604 pages read'**
  String khatmPagesRead(int read);

  /// No description provided for @khatmToday.
  ///
  /// In en, this message translates to:
  /// **'Today: {read} of {target} pages'**
  String khatmToday(int read, int target);

  /// No description provided for @khatmDaysLeft.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{Last day} other{{days} days left}}'**
  String khatmDaysLeft(int days);

  /// No description provided for @khatmEnds.
  ///
  /// In en, this message translates to:
  /// **'ends {date}'**
  String khatmEnds(String date);

  /// No description provided for @khatmPastEnd.
  ///
  /// In en, this message translates to:
  /// **'Past the planned end'**
  String get khatmPastEnd;

  /// No description provided for @khatmPagesLeft.
  ///
  /// In en, this message translates to:
  /// **'{pages, plural, =1{1 page left} other{{pages} pages left}}'**
  String khatmPagesLeft(int pages);

  /// No description provided for @khatmContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue khatm (page {page})'**
  String khatmContinue(int page);

  /// No description provided for @khatmChangeEnd.
  ///
  /// In en, this message translates to:
  /// **'Change end date'**
  String get khatmChangeEnd;

  /// No description provided for @khatmStop.
  ///
  /// In en, this message translates to:
  /// **'Stop this khatm'**
  String get khatmStop;

  /// No description provided for @khatmStopTitle.
  ///
  /// In en, this message translates to:
  /// **'Stop this khatm?'**
  String get khatmStopTitle;

  /// No description provided for @khatmStopBody.
  ///
  /// In en, this message translates to:
  /// **'The pages read in this plan will be forgotten. Your reading log and finished khatms are kept.'**
  String get khatmStopBody;

  /// No description provided for @khatmStopConfirm.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get khatmStopConfirm;

  /// No description provided for @khatmSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the khatm plan. Try again.'**
  String get khatmSaveFailed;

  /// No description provided for @khatmFinished.
  ///
  /// In en, this message translates to:
  /// **'Finished khatms'**
  String get khatmFinished;

  /// No description provided for @khatmCompletedOn.
  ///
  /// In en, this message translates to:
  /// **'Completed {date}'**
  String khatmCompletedOn(String date);

  /// No description provided for @khatmInDays.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{in 1 day} other{in {days} days}}'**
  String khatmInDays(int days);

  /// No description provided for @khatmComplete.
  ///
  /// In en, this message translates to:
  /// **'Khatm complete'**
  String get khatmComplete;

  /// No description provided for @khatmSection.
  ///
  /// In en, this message translates to:
  /// **'Khatm'**
  String get khatmSection;

  /// No description provided for @khatmCard.
  ///
  /// In en, this message translates to:
  /// **'{read} of 604 pages'**
  String khatmCard(int read);

  /// No description provided for @semKhatmToday.
  ///
  /// In en, this message translates to:
  /// **'Khatm: {read} of {target} pages read today'**
  String semKhatmToday(int read, int target);

  /// No description provided for @addNote.
  ///
  /// In en, this message translates to:
  /// **'Add a note'**
  String get addNote;

  /// No description provided for @editNote.
  ///
  /// In en, this message translates to:
  /// **'Edit note'**
  String get editNote;

  /// No description provided for @noteOn.
  ///
  /// In en, this message translates to:
  /// **'Note on {reference}'**
  String noteOn(String reference);

  /// No description provided for @noteHint.
  ///
  /// In en, this message translates to:
  /// **'Write your note'**
  String get noteHint;

  /// No description provided for @saveNote.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveNote;

  /// No description provided for @deleteNote.
  ///
  /// In en, this message translates to:
  /// **'Delete note'**
  String get deleteNote;

  /// No description provided for @noteSaved.
  ///
  /// In en, this message translates to:
  /// **'Note saved'**
  String get noteSaved;

  /// No description provided for @noteDeleted.
  ///
  /// In en, this message translates to:
  /// **'Note deleted'**
  String get noteDeleted;

  /// No description provided for @noteSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the note. Your text is still here.'**
  String get noteSaveFailed;

  /// No description provided for @noteDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not delete the note.'**
  String get noteDeleteFailed;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @semNote.
  ///
  /// In en, this message translates to:
  /// **'note'**
  String get semNote;

  /// No description provided for @notesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Notes} =1{1 note} other{{count} notes}}'**
  String notesCount(int count);

  /// No description provided for @noNotesHint.
  ///
  /// In en, this message translates to:
  /// **'Tap an ayah, then Add a note. Your notes appear here.'**
  String get noNotesHint;

  /// No description provided for @reviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Count this reading?'**
  String get reviewTitle;

  /// No description provided for @reviewExplanation.
  ///
  /// In en, this message translates to:
  /// **'These pages stayed on screen long enough to read. Untick any you did not read.'**
  String get reviewExplanation;

  /// No description provided for @reviewCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Count nothing} =1{Count 1 page} other{Count {count} pages}}'**
  String reviewCount(int count);

  /// No description provided for @reviewNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get reviewNotNow;

  /// No description provided for @reviewDiscard.
  ///
  /// In en, this message translates to:
  /// **'Don’t count these'**
  String get reviewDiscard;

  /// No description provided for @reviewCounted.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 page counted} other{{count} pages counted}}'**
  String reviewCounted(int count);

  /// No description provided for @reviewFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save your reading. It is still waiting; try again.'**
  String get reviewFailed;

  /// No description provided for @reviewWaiting.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 page waiting to be counted} other{{count} pages waiting to be counted}}'**
  String reviewWaiting(int count);

  /// No description provided for @reviewAction.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get reviewAction;

  /// No description provided for @khatmMap.
  ///
  /// In en, this message translates to:
  /// **'Pages read'**
  String get khatmMap;

  /// No description provided for @khatmMapHint.
  ///
  /// In en, this message translates to:
  /// **'Tap a juz to mark its pages read or unread: to fix a mistake, or to add reading from a paper mushaf.'**
  String get khatmMapHint;

  /// No description provided for @semJuzTile.
  ///
  /// In en, this message translates to:
  /// **'Juz {juz}, {read} of {total} pages read'**
  String semJuzTile(int juz, int read, int total);

  /// No description provided for @khatmJuzPages.
  ///
  /// In en, this message translates to:
  /// **'Pages {first}–{last} · {read} of {total} read'**
  String khatmJuzPages(int first, int last, int read, int total);

  /// No description provided for @khatmMarkAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get khatmMarkAllRead;

  /// No description provided for @khatmMarkAllUnread.
  ///
  /// In en, this message translates to:
  /// **'Mark all unread'**
  String get khatmMarkAllUnread;

  /// No description provided for @translationAndTafsir.
  ///
  /// In en, this message translates to:
  /// **'Translation and tafsir'**
  String get translationAndTafsir;

  /// No description provided for @translationAndTafsirDetail.
  ///
  /// In en, this message translates to:
  /// **'The meaning of each ayah, from trusted publishers'**
  String get translationAndTafsirDetail;

  /// No description provided for @chooseTranslation.
  ///
  /// In en, this message translates to:
  /// **'Choose a translation'**
  String get chooseTranslation;

  /// No description provided for @chooseTafsir.
  ///
  /// In en, this message translates to:
  /// **'Choose a tafsir'**
  String get chooseTafsir;

  /// No description provided for @chooseTextExplanation.
  ///
  /// In en, this message translates to:
  /// **'Each text is shown exactly as its publisher issued it.'**
  String get chooseTextExplanation;

  /// No description provided for @chooseText.
  ///
  /// In en, this message translates to:
  /// **'Choose the text'**
  String get chooseText;

  /// No description provided for @textLanguageEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get textLanguageEn;

  /// No description provided for @textLanguageFr.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get textLanguageFr;

  /// No description provided for @textLanguageAr.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get textLanguageAr;

  /// No description provided for @inLanguage.
  ///
  /// In en, this message translates to:
  /// **'In {language}'**
  String inLanguage(String language);

  /// No description provided for @textSourceLine.
  ///
  /// In en, this message translates to:
  /// **'{credit} · version {version} · QuranEnc.com'**
  String textSourceLine(String credit, String version);

  /// No description provided for @translationNote.
  ///
  /// In en, this message translates to:
  /// **'A translation conveys the meanings of the Quran; it is not the Quran itself.'**
  String get translationNote;

  /// No description provided for @footnotes.
  ///
  /// In en, this message translates to:
  /// **'Footnotes'**
  String get footnotes;

  /// No description provided for @previousAyah.
  ///
  /// In en, this message translates to:
  /// **'Previous ayah'**
  String get previousAyah;

  /// No description provided for @nextAyah.
  ///
  /// In en, this message translates to:
  /// **'Next ayah'**
  String get nextAyah;

  /// No description provided for @textLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'This text could not be opened. Reinstalling Rafiq should fix it.'**
  String get textLoadFailed;

  /// No description provided for @listenComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Listening to the recitation is coming soon.'**
  String get listenComingSoon;

  /// No description provided for @yourReading.
  ///
  /// In en, this message translates to:
  /// **'Your reading'**
  String get yourReading;

  /// No description provided for @readingRun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day in a row} other{{count} days in a row}}'**
  String readingRun(int count);

  /// No description provided for @readingRunNone.
  ///
  /// In en, this message translates to:
  /// **'Read a page today to start.'**
  String get readingRunNone;

  /// No description provided for @readingBestRun.
  ///
  /// In en, this message translates to:
  /// **'Best: {days}'**
  String readingBestRun(String days);

  /// No description provided for @daysCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String daysCount(int count);

  /// No description provided for @daysReadThisYear.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No days read yet this year} =1{1 day read this year} other{{count} days read this year}}'**
  String daysReadThisYear(int count);

  /// No description provided for @pagesThisMonth.
  ///
  /// In en, this message translates to:
  /// **'Pages this month'**
  String get pagesThisMonth;

  /// No description provided for @daysThisYear.
  ///
  /// In en, this message translates to:
  /// **'Days read this year'**
  String get daysThisYear;

  /// No description provided for @dayPages.
  ///
  /// In en, this message translates to:
  /// **'{day}: {pages}'**
  String dayPages(String day, String pages);

  /// No description provided for @lastSevenDays.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get lastSevenDays;

  /// No description provided for @chartLess.
  ///
  /// In en, this message translates to:
  /// **'Less'**
  String get chartLess;

  /// No description provided for @chartMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get chartMore;

  /// No description provided for @semReadingGrid.
  ///
  /// In en, this message translates to:
  /// **'Reading chart, the last {weeks} weeks: {days}.'**
  String semReadingGrid(int weeks, String days);

  /// No description provided for @daysWithReading.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{no day read} =1{1 day read} other{{count} days read}}'**
  String daysWithReading(int count);

  /// No description provided for @consistencyHadith.
  ///
  /// In en, this message translates to:
  /// **'“The most beloved deeds to Allah are the most consistent, even if they are small.”'**
  String get consistencyHadith;

  /// No description provided for @consistencyHadithSource.
  ///
  /// In en, this message translates to:
  /// **'Al-Bukhari and Muslim'**
  String get consistencyHadithSource;

  /// No description provided for @dailyReminder.
  ///
  /// In en, this message translates to:
  /// **'Daily reminder'**
  String get dailyReminder;

  /// No description provided for @dailyReminderDetail.
  ///
  /// In en, this message translates to:
  /// **'Around {time}, on days you haven’t read yet'**
  String dailyReminderDetail(String time);

  /// No description provided for @dailyReminderOff.
  ///
  /// In en, this message translates to:
  /// **'A notification on days you haven’t read yet'**
  String get dailyReminderOff;

  /// No description provided for @reminderTime.
  ///
  /// In en, this message translates to:
  /// **'Reminder time'**
  String get reminderTime;

  /// No description provided for @reminderOfferTitle.
  ///
  /// In en, this message translates to:
  /// **'A daily reminder?'**
  String get reminderOfferTitle;

  /// No description provided for @reminderOfferBody.
  ///
  /// In en, this message translates to:
  /// **'Rafiq can remind you each day at a time you choose. On days you have already read, it stays quiet.'**
  String get reminderOfferBody;

  /// No description provided for @reminderOfferAt.
  ///
  /// In en, this message translates to:
  /// **'Remind me at {time}'**
  String reminderOfferAt(String time);

  /// No description provided for @reminderOtherTime.
  ///
  /// In en, this message translates to:
  /// **'Another time'**
  String get reminderOtherTime;

  /// No description provided for @reminderSet.
  ///
  /// In en, this message translates to:
  /// **'Reminder set for {time}'**
  String reminderSet(String time);

  /// No description provided for @reminderBlocked.
  ///
  /// In en, this message translates to:
  /// **'Notifications are off for Rafiq. You can turn them on in the phone’s settings.'**
  String get reminderBlocked;

  /// No description provided for @reminderChannel.
  ///
  /// In en, this message translates to:
  /// **'Daily reading reminder'**
  String get reminderChannel;

  /// No description provided for @reminderTitle.
  ///
  /// In en, this message translates to:
  /// **'Your daily reading'**
  String get reminderTitle;

  /// No description provided for @reminderBody.
  ///
  /// In en, this message translates to:
  /// **'Continue at {surah}, page {page}.'**
  String reminderBody(String surah, int page);

  /// No description provided for @reminderBodyTarget.
  ///
  /// In en, this message translates to:
  /// **'{pages} today. Continue at {surah}, page {page}.'**
  String reminderBodyTarget(String pages, String surah, int page);

  /// No description provided for @goalKhatmToday.
  ///
  /// In en, this message translates to:
  /// **'Khatm today: {pages}'**
  String goalKhatmToday(String pages);

  /// No description provided for @backToNotes.
  ///
  /// In en, this message translates to:
  /// **'Back to notes'**
  String get backToNotes;

  /// No description provided for @backToBookmarks.
  ///
  /// In en, this message translates to:
  /// **'Back to bookmarks'**
  String get backToBookmarks;

  /// No description provided for @backToSurahs.
  ///
  /// In en, this message translates to:
  /// **'Back to surahs'**
  String get backToSurahs;

  /// No description provided for @backToKhatm.
  ///
  /// In en, this message translates to:
  /// **'Back to the khatm'**
  String get backToKhatm;

  /// No description provided for @backToSearch.
  ///
  /// In en, this message translates to:
  /// **'Back to search'**
  String get backToSearch;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['ar', 'en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError('AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
