// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appName => 'Rafiq';

  @override
  String get needsYourAction => 'Action requise';

  @override
  String get dismiss => 'Fermer';

  @override
  String get undo => 'Annuler';

  @override
  String get clear => 'Effacer';

  @override
  String get settings => 'Réglages';

  @override
  String get statusReady => 'Prêt à suivre';

  @override
  String get statusStopped => 'Suivi arrêté';

  @override
  String get statusConnecting => 'Connexion…';

  @override
  String get statusListening => 'À l’écoute de l’imam';

  @override
  String get statusFollowing => 'Suit l’imam';

  @override
  String get statusFatiha => 'Al-Fatiha';

  @override
  String get statusNoNewMatch => 'Rien de nouveau reconnu';

  @override
  String get statusLittleSound => 'Peu de son';

  @override
  String get statusNotSure => 'Pas sûr';

  @override
  String get statusNotMatching => 'Ne correspond pas au Coran';

  @override
  String get statusReconnecting => 'Reconnexion…';

  @override
  String get statusStopping => 'Arrêt…';

  @override
  String get captionReady => 'Lancez le suivi quand l’imam commence. Aucun réglage nécessaire.';

  @override
  String get captionStopped => 'La dernière position reste affichée.';

  @override
  String get captionConnecting => 'La première fois, le serveur de reconnaissance charge son modèle vocal.';

  @override
  String get captionListening => 'Le verset apparaît après quelques mots.';

  @override
  String get captionNoNewMatch =>
      'Du son arrive, mais rien de nouveau n’a correspondu au Coran depuis plus de 10 secondes.';

  @override
  String get captionLittleSound => 'Le micro capte très peu de son depuis plus de 10 secondes.';

  @override
  String captionStillShowing(int ayah) {
    return 'Le verset $ayah reste affiché.';
  }

  @override
  String captionStillShowingConfirmed(int ayah) {
    return 'Le verset $ayah, le dernier confirmé, reste affiché.';
  }

  @override
  String get captionNotSure => 'Le dernier verset sûr reste affiché.';

  @override
  String get captionNotMatching =>
      'Le dernier verset sûr reste affiché. Cela arrive pendant les douʿâʾ ou quand les mots ne sont pas clairs.';

  @override
  String get captionReconnecting => 'Le micro continue d’écouter pendant ce temps.';

  @override
  String repeatedText(String refs) {
    return 'Texte répété — peut aussi être $refs';
  }

  @override
  String get overlineAyah => 'VERSET';

  @override
  String get overlineLastSure => 'DERNIER SÛR';

  @override
  String get semNoPosition => 'Aucune position pour l’instant';

  @override
  String semSurahAyah(String surah, int ayah) {
    return 'Sourate $surah, verset $ayah';
  }

  @override
  String semSurahAyahNotSure(String surah, int ayah) {
    return 'Sourate $surah, verset $ayah, pas sûr';
  }

  @override
  String get hintOpenSurahList => 'ouvrir la liste des sourates';

  @override
  String get tooltipSurahs => 'Sourates';

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
      other: '$count versets',
      one: '1 verset',
    );
    return '$_temp0';
  }

  @override
  String surahHeaderMeta(String name, int number, String ayahs) {
    return '$name · $number · $ayahs';
  }

  @override
  String semSurahHeader(String name, int number) {
    return 'Sourate $name, $number';
  }

  @override
  String get tooltipStayOnSurah => 'Rester sur cette sourate';

  @override
  String tooltipLocked(String scope) {
    return 'Limité à $scope. Touchez pour libérer.';
  }

  @override
  String get tooltipTonight => 'Point de départ de ce soir';

  @override
  String get tooltipBackToReading => 'Retour à la lecture';

  @override
  String get tooltipRemoveHint => 'Retirer l’indication';

  @override
  String hintTonightSurah(String surah) {
    return 'Ce soir : $surah';
  }

  @override
  String hintTonightJuz(int juz) {
    return 'Ce soir : Juz $juz';
  }

  @override
  String lastNightEnded(String place) {
    return 'Hier soir, arrêt à $place.';
  }

  @override
  String get noticePausedTitle => 'Suivi en pause';

  @override
  String get noticePausedBody => 'L’application est passée en arrière-plan. La dernière position reste affichée.';

  @override
  String get actionResume => 'Reprendre';

  @override
  String get actionTryAgain => 'Réessayer';

  @override
  String get noticeMicPermissionTitle => 'Rafiq a besoin du micro';

  @override
  String get noticeMicPermissionBody =>
      'Il écoute la récitation de l’imam pour trouver le verset. Si vous l’avez refusé, autorisez-le dans les réglages du téléphone : Applications → Rafiq → Autorisations → Micro.';

  @override
  String get noticeMicStoppedTitle => 'Le micro a cessé de fonctionner';

  @override
  String get noticeMicStoppedBody =>
      'Rafiq n’a pas pu utiliser le micro. Vérifiez qu’aucune autre application n’enregistre, puis réessayez.';

  @override
  String get noticeUnreachableTitle => 'Serveur de reconnaissance injoignable';

  @override
  String get noticeUnreachableBody =>
      'Cette version reconnaît sur un ordinateur du même Wi-Fi. Vérifiez qu’il fonctionne et que l’adresse dans Réglages est correcte.';

  @override
  String get actionTestConnection => 'Tester la connexion';

  @override
  String get noticeServerStoppedTitle => 'Reconnaissance arrêtée';

  @override
  String get emptyListening => 'Placez le téléphone là où il entend l’imam.';

  @override
  String get emptyIdle => 'Rafiq écoute l’imam et affiche la sourate et le verset, en direct.';

  @override
  String get browseSurahs => 'Parcourir les sourates';

  @override
  String get controlPreparing => 'Préparation…';

  @override
  String get controlFinishing => 'Fin des derniers mots…';

  @override
  String get controlStop => 'Arrêter le suivi';

  @override
  String get controlStart => 'Suivre l’imam';

  @override
  String get semStartFollowing => 'Commencer à suivre l’imam';

  @override
  String get hearingSound => 'Son capté';

  @override
  String get veryLittleSound => 'Très peu de son';

  @override
  String get backToImam => 'Retour à l’imam';

  @override
  String backToImamAt(String ref) {
    return 'Retour à l’imam · $ref';
  }

  @override
  String ayahSheetTitle(String surah, int ayah) {
    return '$surah · verset $ayah';
  }

  @override
  String get imamJumpExplanation => 'Rafiq passe à ce verset et continue le suivi à partir de là.';

  @override
  String get startFirstExplanation => 'Lancez d’abord le suivi, puis touchez le verset où se trouve l’imam.';

  @override
  String get imamIsHere => 'L’imam est ici';

  @override
  String get unlockAll => 'Libérer : chercher à nouveau dans tout le Coran';

  @override
  String stayOnSurah(String surah) {
    return 'Rester sur $surah';
  }

  @override
  String get stayOnThisSurah => 'Rester sur cette sourate';

  @override
  String get lockExplanation =>
      'Rafiq ne cherchera pas dans d’autres sourates tant que vous ne libérez pas. Al-Fatiha reste reconnue à chaque rakʿa.';

  @override
  String get hintSheetTitle => 'Point de départ de ce soir';

  @override
  String get hintSheetExplanation =>
      'Facultatif. Rafiq trouve l’imam sans cela ; une indication fait seulement apparaître le premier verset plus tôt.';

  @override
  String get hintSheetRestarts => 'La modifier relance l’écoute.';

  @override
  String get hintNone => 'Aucune';

  @override
  String get hintSurah => 'Sourate';

  @override
  String get hintJuz => 'Juz';

  @override
  String get hintNoneExplanation => 'Sans indication : Rafiq cherche dans tout le Coran.';

  @override
  String get searchByNameOrNumber => 'Chercher par nom ou numéro';

  @override
  String get introTitle => 'Mode Tarawih';

  @override
  String get introLead => 'Rafiq écoute l’imam et affiche le verset récité, en direct.';

  @override
  String get introMic => 'Le micro n’est utilisé que pendant le suivi. L’écran reste allumé.';

  @override
  String get introServer =>
      'Cette version de test reconnaît sur un ordinateur du même Wi-Fi (Réglages → Serveur de reconnaissance).';

  @override
  String get introHafs => 'Il suit uniquement la récitation Ḥafṣ ʿan ʿĀṣim.';

  @override
  String get introCorrect =>
      'S’il se trompe, touchez le verset où se trouve l’imam. Quand il n’est pas sûr, il le dit au lieu de deviner.';

  @override
  String get notNow => 'Plus tard';

  @override
  String semAyah(int ayah) {
    return 'Verset $ayah';
  }

  @override
  String semAyahImamHere(int ayah) {
    return 'Verset $ayah, l’imam est ici';
  }

  @override
  String get hintMarkImam => 'indiquer où est l’imam';

  @override
  String get hintAyahActions => 'actions sur le verset';

  @override
  String get tooltipNavigate => 'Sourates, juz et signets';

  @override
  String get tooltipSearch => 'Chercher dans le Coran';

  @override
  String semReaderBar(String surah, int ayah, int juz, int page) {
    return '$surah, verset $ayah. Juz $juz, page $page. Ouvrir l’index';
  }

  @override
  String get taraweeh => 'Tarawih';

  @override
  String get semTaraweehEntry => 'Tarawih : suivre l’imam';

  @override
  String get bookmark => 'Ajouter un signet';

  @override
  String get removeBookmark => 'Retirer le signet';

  @override
  String get copyAyah => 'Copier le verset';

  @override
  String bookmarked(String ref) {
    return 'Signet ajouté : $ref';
  }

  @override
  String get bookmarkFailed => 'Le signet n’a pas pu être enregistré. Réessayez.';

  @override
  String get bookmarkRemoved => 'Signet retiré';

  @override
  String get bookmarkRemoveFailed => 'Le signet n’a pas pu être retiré. Réessayez.';

  @override
  String copied(String ref) {
    return 'Copié : $ref';
  }

  @override
  String get goTo => 'Aller à';

  @override
  String get tabSurahs => 'Sourates';

  @override
  String get tabJuz => 'Juz';

  @override
  String get tabPages => 'Pages';

  @override
  String get tabBookmarks => 'Signets';

  @override
  String fromPlacePage(String place, int page) {
    return 'Depuis $place · Page $page';
  }

  @override
  String fromPlaceJuz(String place, int juz) {
    return 'Depuis $place · Juz $juz';
  }

  @override
  String get whereTaraweehEnded => 'Là où les Tarawih se sont arrêtées';

  @override
  String get today => 'aujourd’hui';

  @override
  String get yesterday => 'hier';

  @override
  String daysAgo(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'il y a $days jours',
      one: 'il y a 1 jour',
    );
    return '$_temp0';
  }

  @override
  String get noBookmarks => 'Aucun signet pour l’instant. Pendant la lecture, touchez un verset pour l’ajouter.';

  @override
  String get searchHint => 'Sourate, 2:255, page 50 ou mots en arabe';

  @override
  String searchFirstOf(int shown, int total) {
    return 'Les $shown premiers versets sur $total';
  }

  @override
  String searchTooShort(int count) {
    return 'Tapez au moins $count lettres pour chercher dans le texte.';
  }

  @override
  String searchNothing(String query) {
    return 'Aucun résultat pour « $query ».';
  }

  @override
  String get searchBy => 'Chercher par';

  @override
  String get searchHelpSurah => 'Une sourate : Al-Kahf, الكهف ou 18';

  @override
  String get searchHelpAyah => 'Un verset : 2:255';

  @override
  String get searchHelpPlace => 'Une page ou un juz : page 50, juz 30';

  @override
  String get searchHelpWords => 'Des mots du Coran, en arabe : ٱلْحَمْدُ لِلَّهِ (avec ou sans voyelles)';

  @override
  String surahNumberAyahs(int number, String ayahs) {
    return 'Sourate $number · $ayahs';
  }

  @override
  String get groupReading => 'Lecture';

  @override
  String get quranTextSize => 'Taille du texte coranique';

  @override
  String get appearance => 'Apparence';

  @override
  String get appearanceExplanation => 'La lecture suit votre téléphone. Le mode Tarawih a son propre réglage plus bas.';

  @override
  String get themeDark => 'Sombre';

  @override
  String get themeLight => 'Clair';

  @override
  String get themeSystem => 'Système';

  @override
  String get language => 'Langue';

  @override
  String get languageExplanation => 'Le texte du Coran est toujours affiché tel qu’il a été révélé, en arabe.';

  @override
  String get languageSystem => 'Système';

  @override
  String get groupTaraweeh => 'Tarawih';

  @override
  String get darkDuringTaraweeh => 'Sombre pendant les Tarawih';

  @override
  String get darkDuringTaraweehDetail => 'Le mode Tarawih reste sombre, quelle que soit l’apparence de la lecture';

  @override
  String get keepScreenOn => 'Garder l’écran allumé pendant le suivi';

  @override
  String get keepScreenOnDetail => 'Recommandé pendant la prière';

  @override
  String get groupRecitation => 'Récitation';

  @override
  String get riwaya => 'Riwâya';

  @override
  String get hafs => 'Ḥafṣ ʿan ʿĀṣim';

  @override
  String get hafsOnly =>
      'Rafiq reconnaît et numérote les versets selon la riwâya de Ḥafṣ uniquement. Qâloun et Warch ne sont pas encore pris en charge.';

  @override
  String get groupServer => 'Serveur de reconnaissance';

  @override
  String get serverExplanation =>
      'Cette version reconnaît sur un ordinateur du même Wi-Fi ; elle ne fonctionne pas sans lui.';

  @override
  String get serverAddress => 'Adresse du serveur';

  @override
  String get serverHelp =>
      'Lancez le serveur sur l’ordinateur avec :  python -m rafiq_server --host 0.0.0.0\npuis saisissez son adresse Wi-Fi et son port. Sur l’émulateur Android, utilisez 10.0.2.2:8765.';

  @override
  String get groupDeveloper => 'Développeur';

  @override
  String get showDiagnostics => 'Afficher les diagnostics';

  @override
  String get showDiagnosticsDetail => 'Ce que le modèle vocal entend, pour les tests';

  @override
  String get asrBench => 'Test de reconnaissance sur l’appareil';

  @override
  String get asrBenchDetail => 'Ce téléphone peut-il reconnaître l’imam sans l’ordinateur ? Un test, pas une fonction.';

  @override
  String get groupAbout => 'À propos';

  @override
  String get aboutLead =>
      'Rafiq est un lecteur du Coran qui peut suivre l’imam pendant les Tarawih et afficher la sourate et le verset récités.';

  @override
  String get textSizeSize => 'Taille';

  @override
  String get textSizeNote => 'Les numéros de verset et l’interligne suivent la taille du texte.';

  @override
  String get healthFailed => 'Échec';

  @override
  String healthConnected(int ms, String device) {
    return 'Connecté · $ms ms · modèle vocal $device';
  }

  @override
  String get healthReadyOnFirstUse => 'prêt à la première utilisation';

  @override
  String healthNoAsr(int ms) {
    return 'Connecté · $ms ms · reconnaissance vocale NON installée';
  }

  @override
  String get layout => 'Disposition';

  @override
  String get layoutExplanation =>
      'Défilement : le Coran comme un texte continu. Pages : les 604 pages du mushaf de Médine.';

  @override
  String get layoutScroll => 'Défilement';

  @override
  String get layoutPages => 'Pages';

  @override
  String get tooltipPageView => 'Lire page par page';

  @override
  String get tooltipScrollView => 'Lire en défilement continu';

  @override
  String get share => 'Partager';

  @override
  String get shareAyah => 'Partager le verset';

  @override
  String get shareAsImage => 'Partager en image';

  @override
  String get shareAsText => 'Partager en texte';

  @override
  String get shareFailed => 'Le partage a échoué. Réessayez.';

  @override
  String get dailyGoal => 'Objectif de lecture quotidien';

  @override
  String get dailyGoalExplanation =>
      'Une page compte quand vous la dépassez en lisant, par défilement ou en tournant. Les sauts ne comptent pas. 20 pages par jour, c’est un juz : tout le Coran en un mois.';

  @override
  String get dailyGoalOff => 'Désactivé';

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
    return 'Aujourd’hui $read/$goal';
  }

  @override
  String semTodayProgress(int read, int goal) {
    return '$read pages lues sur $goal aujourd’hui';
  }

  @override
  String khatmProgress(int page, int total, int percent) {
    return 'Page $page sur $total · $percent %';
  }

  @override
  String get navRead => 'Lire';

  @override
  String get navSurahs => 'Sourates';

  @override
  String get navBookmarks => 'Signets';

  @override
  String get navMore => 'Plus';

  @override
  String get continueReading => 'Reprendre la lecture';

  @override
  String bookmarksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count signets',
      one: '1 signet',
      zero: 'Signets',
    );
    return '$_temp0';
  }

  @override
  String get sortBookmarks => 'Trier les signets';

  @override
  String get sortNewest => 'Plus récents d’abord';

  @override
  String get sortQuranOrder => 'Dans l’ordre du Coran';

  @override
  String get noBookmarksHint =>
      'Aucun signet pour l’instant. Pendant la lecture, appuyez longuement sur un verset pour l’ajouter.';

  @override
  String get scrubberLabel => 'Parcourir le Coran';

  @override
  String get tooltipOpenSurahs => 'Sourates, juz et pages';

  @override
  String get comingSoon => 'Bientôt';

  @override
  String get soon => 'Bientôt';

  @override
  String get soonRecitation => 'Récitation audio';

  @override
  String get soonRecitationDetail => 'Écouter un verset, une page ou une sourate';

  @override
  String get soonTranslation => 'Traductions';

  @override
  String get soonTranslationDetail => 'Le sens à côté de l’arabe, dans votre langue';

  @override
  String get soonTafsir => 'Tafsir';

  @override
  String get soonTafsirDetail => 'Le commentaire de chaque verset';

  @override
  String get soonNotes => 'Notes';

  @override
  String get soonNotesDetail => 'Vos propres notes sur un verset';

  @override
  String get soonOffline => 'Tarawih sans ordinateur';

  @override
  String get soonOfflineDetail => 'La reconnaissance sur le téléphone lui-même';

  @override
  String get listen => 'Écouter';

  @override
  String get translation => 'Traduction';

  @override
  String get tafsir => 'Tafsir';

  @override
  String get khatmPlanner => 'Plan de khatm';

  @override
  String get khatmPlannerDetail => 'Planifier une lecture complète et la suivre jour après jour';

  @override
  String get khatmExplanation =>
      'Lisez tout le Coran d’ici la date de votre choix. L’objectif du jour s’adapte : lisez en avance et les jours suivants demandent moins.';

  @override
  String get khatmFinishIn => 'Terminer en';

  @override
  String khatmDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days jours',
      one: '1 jour',
    );
    return '$_temp0';
  }

  @override
  String get khatmJuzADay => 'Un juz par jour';

  @override
  String get khatmPickDate => 'Choisir une date';

  @override
  String get khatmLastDay => 'Dernier jour de la khatm';

  @override
  String get khatmStartAt => 'Début';

  @override
  String get khatmFromHere => 'Là où je lis';

  @override
  String get khatmFromBeginning => 'Depuis le début';

  @override
  String khatmPreview(int pages, String date) {
    String _temp0 = intl.Intl.pluralLogic(
      pages,
      locale: localeName,
      other: 'Environ $pages pages par jour',
      one: 'Environ 1 page par jour',
    );
    return '$_temp0 · fin le $date';
  }

  @override
  String get khatmStart => 'Commencer la khatm';

  @override
  String khatmPagesRead(int read) {
    return '$read pages lues sur 604';
  }

  @override
  String khatmToday(int read, int target) {
    return 'Aujourd’hui : $read sur $target pages';
  }

  @override
  String khatmDaysLeft(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Encore $days jours',
      one: 'Dernier jour',
    );
    return '$_temp0';
  }

  @override
  String khatmEnds(String date) {
    return 'fin le $date';
  }

  @override
  String get khatmPastEnd => 'Date de fin dépassée';

  @override
  String khatmPagesLeft(int pages) {
    String _temp0 = intl.Intl.pluralLogic(
      pages,
      locale: localeName,
      other: '$pages pages restantes',
      one: '1 page restante',
    );
    return '$_temp0';
  }

  @override
  String khatmContinue(int page) {
    return 'Continuer la khatm (page $page)';
  }

  @override
  String get khatmChangeEnd => 'Changer la date de fin';

  @override
  String get khatmStop => 'Arrêter cette khatm';

  @override
  String get khatmStopTitle => 'Arrêter cette khatm ?';

  @override
  String get khatmStopBody =>
      'Les pages lues dans ce plan seront oubliées. Votre historique de lecture et les khatms terminées sont conservés.';

  @override
  String get khatmStopConfirm => 'Arrêter';

  @override
  String get khatmSaveFailed => 'Impossible d’enregistrer le plan de khatm. Réessayez.';

  @override
  String get khatmFinished => 'Khatms terminées';

  @override
  String khatmCompletedOn(String date) {
    return 'Terminée le $date';
  }

  @override
  String khatmInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'en $days jours',
      one: 'en 1 jour',
    );
    return '$_temp0';
  }

  @override
  String get khatmComplete => 'Khatm terminée';

  @override
  String get khatmSection => 'Khatm';

  @override
  String khatmCard(int read) {
    return '$read pages sur 604';
  }

  @override
  String semKhatmToday(int read, int target) {
    return 'Khatm : $read pages lues sur $target aujourd’hui';
  }
}
