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
  String get statusConnecting => 'Mise en route…';

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
  String get captionConnecting => 'Chargement du modèle vocal. La première fois prend un peu plus de temps.';

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
  String get statusRepeated => 'Mots répétés';

  @override
  String captionRepeatedInSurah(String surah) {
    return 'Ces mots reviennent dans la sourate $surah. En attente de la suite pour savoir quel verset.';
  }

  @override
  String get captionRepeatedAcross =>
      'Ces mots figurent dans plusieurs sourates. En attente de la suite, ou choisissez ci-dessous.';

  @override
  String get chooseAyahInText => 'Choisir le verset dans le texte';

  @override
  String semSurahAyahUnknown(String surah) {
    return 'Sourate $surah, verset pas encore connu';
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
      'Rafiq ne cherche que dans cette sourate et la suivante, et avance avec l’imam. Al-Fatiha reste reconnue à chaque rakʿa.';

  @override
  String lockedSnack(String surah) {
    return 'Reste sur $surah, puis la sourate suivante';
  }

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
  String get taraweehEndedHere => 'Les Tarawih se sont arrêtées ici';

  @override
  String get taraweehEndUnknown => 'Pas clair d’après ce qui a été entendu. Touchez un verset pour l’indiquer.';

  @override
  String taraweehEndSet(String place) {
    return 'Les Tarawih se sont arrêtées à $place';
  }

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
      'Le mode Tarawih reconnaît alors sur cet ordinateur au lieu du téléphone. Pour le développement seulement.';

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
  String get asrBenchDetail =>
      'La vitesse de reconnaissance de ce téléphone. Pour le développement : les extraits de test viennent du serveur.';

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
      'Une page compte quand elle est restée à l’écran assez longtemps pour être lue, et que vous le confirmez après la lecture. 20 pages par jour, c’est un juz : tout le Coran en un mois.';

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

  @override
  String get addNote => 'Ajouter une note';

  @override
  String get editNote => 'Modifier la note';

  @override
  String noteOn(String reference) {
    return 'Note sur $reference';
  }

  @override
  String get noteHint => 'Écrivez votre note';

  @override
  String get saveNote => 'Enregistrer';

  @override
  String get deleteNote => 'Supprimer la note';

  @override
  String get noteSaved => 'Note enregistrée';

  @override
  String get noteDeleted => 'Note supprimée';

  @override
  String get noteSaveFailed => 'Impossible d’enregistrer la note. Votre texte est toujours là.';

  @override
  String get noteDeleteFailed => 'Impossible de supprimer la note.';

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
  String get noNotesHint => 'Touchez un verset, puis Ajouter une note. Vos notes apparaissent ici.';

  @override
  String get reviewTitle => 'Compter cette lecture ?';

  @override
  String get reviewExplanation =>
      'Ces pages sont restées à l’écran assez longtemps pour être lues. Décochez celles que vous n’avez pas lues.';

  @override
  String reviewCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Compter $count pages',
      one: 'Compter 1 page',
      zero: 'Ne rien compter',
    );
    return '$_temp0';
  }

  @override
  String get reviewNotNow => 'Plus tard';

  @override
  String get reviewDiscard => 'Ne pas les compter';

  @override
  String reviewCounted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages comptées',
      one: '1 page comptée',
    );
    return '$_temp0';
  }

  @override
  String get reviewFailed => 'Impossible d’enregistrer votre lecture. Elle reste en attente ; réessayez.';

  @override
  String reviewWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages en attente',
      one: '1 page en attente',
    );
    return '$_temp0';
  }

  @override
  String get reviewAction => 'Vérifier';

  @override
  String get khatmMap => 'Pages lues';

  @override
  String get khatmMapHint =>
      'Touchez un juz pour marquer ses pages lues ou non lues : pour corriger une erreur, ou ajouter une lecture faite dans un mushaf papier.';

  @override
  String semJuzTile(int juz, int read, int total) {
    return 'Juz $juz, $read pages lues sur $total';
  }

  @override
  String khatmJuzPages(int first, int last, int read, int total) {
    return 'Pages $first à $last · $read lues sur $total';
  }

  @override
  String get khatmMarkAllRead => 'Tout marquer lu';

  @override
  String get khatmMarkAllUnread => 'Tout marquer non lu';

  @override
  String get translationAndTafsir => 'Traduction et tafsir';

  @override
  String get translationAndTafsirDetail => 'Le sens de chaque verset, par des éditeurs de confiance';

  @override
  String get chooseTranslation => 'Choisir une traduction';

  @override
  String get chooseTafsir => 'Choisir un tafsir';

  @override
  String get chooseTextExplanation => 'Chaque texte est affiché tel que son éditeur l’a publié.';

  @override
  String get chooseText => 'Choisir le texte';

  @override
  String get textLanguageEn => 'anglais';

  @override
  String get textLanguageFr => 'français';

  @override
  String get textLanguageAr => 'arabe';

  @override
  String inLanguage(String language) {
    return 'En $language';
  }

  @override
  String textSourceLine(String credit, String version) {
    return '$credit · version $version · QuranEnc.com';
  }

  @override
  String get translationNote => 'Une traduction rend le sens du Coran ; elle n’est pas le Coran lui-même.';

  @override
  String get footnotes => 'Notes';

  @override
  String get previousAyah => 'Verset précédent';

  @override
  String get nextAyah => 'Verset suivant';

  @override
  String get textLoadFailed => 'Ce texte n’a pas pu être ouvert. Réinstaller Rafiq devrait régler le problème.';

  @override
  String get yourReading => 'Votre lecture';

  @override
  String readingRun(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count jours d’affilée',
      one: '1 jour d’affilée',
    );
    return '$_temp0';
  }

  @override
  String get readingRunNone => 'Lisez une page aujourd’hui pour commencer.';

  @override
  String readingBestRun(String days) {
    return 'Record : $days';
  }

  @override
  String daysCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count jours',
      one: '1 jour',
    );
    return '$_temp0';
  }

  @override
  String daysReadThisYear(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count jours de lecture cette année',
      one: '1 jour de lecture cette année',
      zero: 'Aucun jour de lecture cette année',
    );
    return '$_temp0';
  }

  @override
  String get pagesThisMonth => 'Pages ce mois-ci';

  @override
  String get daysThisYear => 'Jours de lecture cette année';

  @override
  String dayPages(String day, String pages) {
    return '$day : $pages';
  }

  @override
  String get lastSevenDays => 'Les 7 derniers jours';

  @override
  String get chartLess => 'Moins';

  @override
  String get chartMore => 'Plus';

  @override
  String semReadingGrid(int weeks, String days) {
    return 'Graphique de lecture, les $weeks dernières semaines : $days.';
  }

  @override
  String daysWithReading(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count jours de lecture',
      one: '1 jour de lecture',
      zero: 'aucun jour de lecture',
    );
    return '$_temp0';
  }

  @override
  String get consistencyHadith =>
      '« Les œuvres les plus aimées d’Allah sont les plus constantes, même si elles sont modestes. »';

  @override
  String get consistencyHadithSource => 'Al-Bukhari et Muslim';

  @override
  String get dailyReminder => 'Rappel quotidien';

  @override
  String dailyReminderDetail(String time) {
    return 'Vers $time, les jours où vous n’avez pas encore lu';
  }

  @override
  String get dailyReminderOff => 'Une notification les jours où vous n’avez pas encore lu';

  @override
  String get reminderTime => 'Heure du rappel';

  @override
  String get reminderOfferTitle => 'Un rappel chaque jour ?';

  @override
  String get reminderOfferBody =>
      'Rafiq peut vous le rappeler chaque jour à l’heure de votre choix. Les jours où vous avez déjà lu, il reste silencieux.';

  @override
  String reminderOfferAt(String time) {
    return 'Me le rappeler à $time';
  }

  @override
  String get reminderOtherTime => 'Une autre heure';

  @override
  String reminderSet(String time) {
    return 'Rappel réglé à $time';
  }

  @override
  String get reminderBlocked =>
      'Les notifications sont désactivées pour Rafiq. Vous pouvez les activer dans les réglages du téléphone.';

  @override
  String get reminderChannel => 'Rappel de lecture quotidienne';

  @override
  String get reminderTitle => 'Votre lecture du jour';

  @override
  String reminderBody(String surah, int page) {
    return 'Reprenez à $surah, page $page.';
  }

  @override
  String reminderBodyTarget(String pages, String surah, int page) {
    return '$pages aujourd’hui. Reprenez à $surah, page $page.';
  }

  @override
  String goalKhatmToday(String pages) {
    return 'Khatm aujourd’hui : $pages';
  }

  @override
  String get backToNotes => 'Retour aux notes';

  @override
  String get backToBookmarks => 'Retour aux signets';

  @override
  String get backToSurahs => 'Retour aux sourates';

  @override
  String get backToKhatm => 'Retour au khatm';

  @override
  String get backToSearch => 'Retour à la recherche';

  @override
  String get adhkar => 'Adhkar';

  @override
  String get adhkarDetail => 'Matin, soir, après la prière, avant de dormir';

  @override
  String adhkarNowDetail(String collection) {
    return 'Maintenant : $collection';
  }

  @override
  String get adhkarMorning => 'Adhkar du matin';

  @override
  String get adhkarEvening => 'Adhkar du soir';

  @override
  String get adhkarPrayer => 'Après la prière';

  @override
  String get adhkarSleep => 'Avant de dormir';

  @override
  String get adhkarAnytime => 'À tout moment';

  @override
  String get adhkarMorningWhen => 'Après Fajr';

  @override
  String get adhkarEveningWhen => 'Après Asr';

  @override
  String get adhkarPrayerWhen => 'Après chaque prière obligatoire';

  @override
  String get adhkarSleepWhen => 'Au lit, avant de dormir';

  @override
  String get adhkarAnytimeWhen => 'De courts adhkar pour toute la journée';

  @override
  String get adhkarNow => 'Maintenant';

  @override
  String adhkarProgress(int done, int total) {
    return '$done sur $total aujourd’hui';
  }

  @override
  String get adhkarDoneToday => 'Faits aujourd’hui';

  @override
  String get adhkarTapToCount => 'Touchez un dhikr chaque fois que vous le dites.';

  @override
  String get adhkarStartAgain => 'Recommencer';

  @override
  String get adhkarStartedAgain => 'C’est reparti';

  @override
  String get adhkarAllDone => 'Terminé. Qu’Allah l’accepte de vous.';

  @override
  String adhkarSources(String first, String second) {
    return '$first et $second';
  }

  @override
  String semDhikrCount(int said, int count) {
    return '$said sur $count';
  }

  @override
  String get semDhikrDone => 'Fait';

  @override
  String get hintDhikrCount => 'compter';

  @override
  String get dhikrReminders => 'Rappels de dhikr';

  @override
  String get dhikrRemindersOff => 'Un court dhikr en haut de l’écran de temps en temps, même quand Rafiq est fermé';

  @override
  String dhikrRemindersDetail(String every, String from, String to) {
    return '$every, de $from à $to';
  }

  @override
  String dhikrEvery(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: 'Toutes les $hours heures',
      one: 'Toutes les heures',
    );
    return '$_temp0';
  }

  @override
  String get dhikrHowOften => 'Fréquence';

  @override
  String get dhikrRemindersSet => 'Rappels de dhikr activés';

  @override
  String get dhikrNotificationTitle => 'Souvenez-vous d’Allah';

  @override
  String dhikrHowOftenExplanation(String from, String to) {
    return 'Un court dhikr entre $from et $to, dans une petite carte en haut à droite de l’écran. Elle reste jusqu’à ce que vous la touchiez. Android peut la décaler un peu pour économiser la batterie.';
  }

  @override
  String get dhikrOnScreen => 'À l’écran';

  @override
  String get dhikrOnScreenOn => 'Une petite carte en haut à droite, jusqu’à ce que vous la touchiez';

  @override
  String get dhikrOnScreenOff => 'Non autorisé : chaque dhikr attend dans les notifications';

  @override
  String get dhikrOnScreenAsk =>
      'Rafiq affiche chaque dhikr dans une petite carte en haut à droite de l’écran, par-dessus les autres applis, jusqu’à ce que vous la touchiez. Sur l’écran suivant, trouvez Rafiq dans la liste et autorisez-le à s’afficher par-dessus.';

  @override
  String get dhikrUseNotifications => 'Utiliser les notifications';

  @override
  String get dhikrShowNow => 'En afficher un maintenant';

  @override
  String get dhikrTapToClose => 'Touchez pour fermer';

  @override
  String get prayerTimes => 'Heures de prière';

  @override
  String get prayerTimesDetail => 'Là où vous êtes, avec l’adhan';

  @override
  String prayerNext(String prayer, String time) {
    return 'Prochaine : $prayer, $time';
  }

  @override
  String get prayerFajr => 'Fajr';

  @override
  String get prayerSunrise => 'Lever du soleil';

  @override
  String get prayerDhuhr => 'Dhuhr';

  @override
  String get prayerAsr => 'Asr';

  @override
  String get prayerMaghrib => 'Maghrib';

  @override
  String get prayerIsha => 'Isha';

  @override
  String get prayerIntroTitle => 'Les heures de prière là où vous êtes';

  @override
  String get prayerIntroBody =>
      'Rafiq les calcule sur votre téléphone, d’après la position du soleil. Votre lieu reste sur votre téléphone.';

  @override
  String get useMyLocation => 'Utiliser ma position';

  @override
  String get useMyLocationDetail => 'Approximative, lue une fois, gardée sur votre téléphone';

  @override
  String get chooseCity => 'Choisir une ville';

  @override
  String get prayerNextLabel => 'Prochaine prière';

  @override
  String prayerIn(String duration) {
    return 'dans $duration';
  }

  @override
  String get prayerNow => 'maintenant';

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '$hours h $minutes min';
  }

  @override
  String durationHours(int hours) {
    return '$hours h';
  }

  @override
  String durationMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get prayerPlace => 'Lieu';

  @override
  String get prayerPlaceLocated => 'D’après votre position';

  @override
  String placeAndCountry(String city, String country) {
    return '$city, $country';
  }

  @override
  String get placeTitle => 'Votre lieu';

  @override
  String get searchCity => 'Rechercher une ville';

  @override
  String get placeHelp =>
      'Les heures de prière dépendent du lieu. Utilisez votre position, ou saisissez le nom de votre ville. Dans les deux cas, cela reste sur votre téléphone.';

  @override
  String noCityFound(String query) {
    return 'Aucune ville trouvée pour « $query ». Essayez une autre orthographe, ou une ville plus grande à proximité.';
  }

  @override
  String get locating => 'Recherche de votre position…';

  @override
  String get locationDenied =>
      'La localisation n’est pas autorisée pour Rafiq. Vous pouvez choisir une ville à la place.';

  @override
  String get locationDeniedForever =>
      'La localisation est désactivée pour Rafiq. Autorisez-la dans les réglages du téléphone, ou choisissez une ville.';

  @override
  String get locationServiceOff =>
      'La localisation est désactivée sur ce téléphone. Activez-la, ou choisissez une ville.';

  @override
  String get locationUnavailable =>
      'Votre position n’a pas pu être trouvée. Réessayez dans un instant, ou choisissez une ville.';

  @override
  String get openSettings => 'Ouvrir les réglages';

  @override
  String get prayerNotSaved => 'Cela n’a pas pu être enregistré. Le stockage du téléphone est peut-être plein.';

  @override
  String get prayerUnavailable => 'Les heures de prière ne peuvent pas être calculées pour ce lieu.';

  @override
  String get adhan => 'Adhan';

  @override
  String get adhanOffDetail => 'L’appel à la prière à chaque heure de prière, même quand Rafiq est fermé';

  @override
  String get adhanOnDetail => 'Touchez une prière ci-dessus pour choisir comment elle est annoncée';

  @override
  String get adhanSet => 'Adhan activé';

  @override
  String adhanFor(String prayer) {
    return 'Adhan de $prayer';
  }

  @override
  String get adhanAlertExplanation =>
      'Le son suit le volume des notifications du téléphone, et se tait quand le téléphone est en silencieux.';

  @override
  String get alertSound => 'Adhan';

  @override
  String get alertVibrate => 'Vibreur';

  @override
  String get alertSilent => 'Notification silencieuse';

  @override
  String get alertOff => 'Désactivé';

  @override
  String semAdhanAlert(String alert) {
    return 'Adhan : $alert';
  }

  @override
  String get hintAdhanAlert => 'choisir comment elle est annoncée';

  @override
  String get adhanSound => 'Enregistrement';

  @override
  String get adhanSoundFull => 'L’adhan en entier';

  @override
  String get adhanSoundTakbir => 'Le takbir d’ouverture seulement';

  @override
  String get adhanSoundExplanation =>
      'L’adhan en entier dure environ deux minutes et demie, son takbir d’ouverture une demi-minute. Balayez la notification pour l’arrêter.';

  @override
  String get adhanTest => 'Tester l’adhan';

  @override
  String get adhanTestDetail => 'Le lance maintenant, comme à l’heure de la prière';

  @override
  String get adhanTestTitle => 'Test de l’adhan';

  @override
  String get adhanTestBody => 'Voici comment Rafiq lancera l’adhan. Balayez pour arrêter.';

  @override
  String get adhanLateTitle => 'L’adhan peut arriver en retard';

  @override
  String get adhanLateBody =>
      'Android ne laisse Rafiq lancer l’adhan à la minute que s’il peut régler des alarmes. En attendant, chaque prière reçoit une notification silencieuse, qui peut avoir jusqu’à une heure de retard.';

  @override
  String get adhanAllowAlarms => 'Autoriser les alarmes';

  @override
  String get adhanExactAsk =>
      'Encore une étape : sur l’écran suivant, autorisez Rafiq à régler des alarmes et des rappels, pour que l’adhan arrive à la minute.';

  @override
  String get continueAction => 'Continuer';

  @override
  String get adhanBlockedTitle => 'Les notifications sont désactivées';

  @override
  String get adhanChannelFull => 'Adhan : l’adhan en entier';

  @override
  String get adhanChannelTakbir => 'Adhan : le takbir seulement';

  @override
  String get adhanChannelVibrate => 'Adhan : vibreur';

  @override
  String get adhanChannelSilent => 'Adhan : silencieux';

  @override
  String adhanNotificationTitle(String prayer, String time) {
    return '$prayer · $time';
  }

  @override
  String adhanNotificationBody(String place) {
    return 'C’est l’heure de la prière · $place';
  }

  @override
  String get adhanRenewTitle => 'Ouvrez Rafiq pour garder l’adhan';

  @override
  String get adhanRenewBody =>
      'Rafiq prépare l’adhan un mois à l’avance. Ouvrez-le une fois pour préparer le mois suivant.';

  @override
  String get groupCalculation => 'Calcul';

  @override
  String get prayerMethod => 'Méthode';

  @override
  String get prayerMethodExplanation =>
      'Les mosquées suivent l’autorité de leur pays pour Fajr et Isha. Rafiq la choisit d’après votre lieu. Changez-la si votre mosquée en suit une autre.';

  @override
  String methodAutomatic(String method) {
    return 'Automatique : $method';
  }

  @override
  String get methodMuslimWorldLeague => 'Ligue islamique mondiale';

  @override
  String get methodTunisia => 'Tunisie';

  @override
  String get methodAlgeria => 'Algérie';

  @override
  String get methodMorocco => 'Maroc';

  @override
  String get methodEgypt => 'Égypte';

  @override
  String get methodUmmAlQura => 'Oumm al-Qura, La Mecque';

  @override
  String get methodGulf => 'Région du Golfe';

  @override
  String get methodDubai => 'Dubaï';

  @override
  String get methodKuwait => 'Koweït';

  @override
  String get methodQatar => 'Qatar';

  @override
  String get methodJordan => 'Jordanie';

  @override
  String get methodTurkiye => 'Turquie (Diyanet)';

  @override
  String get methodFrance => 'France (UOIF, 12°)';

  @override
  String get methodKarachi => 'Karachi (Pakistan, Inde, Bangladesh)';

  @override
  String get methodNorthAmerica => 'Amérique du Nord (ISNA)';

  @override
  String get methodMoonsighting => 'Moonsighting Committee';

  @override
  String get methodSingapore => 'Singapour, Malaisie';

  @override
  String get methodIndonesia => 'Indonésie';

  @override
  String get methodRussia => 'Russie';

  @override
  String get methodPortugal => 'Portugal';

  @override
  String get methodTehran => 'Téhéran';

  @override
  String get methodJafari => 'Jafarite';

  @override
  String get asrTime => 'Asr';

  @override
  String get asrExplanation =>
      'Asr commence quand une ombre est aussi longue que l’objet qui la projette, ou deux fois plus longue selon l’école hanafite.';

  @override
  String get asrStandard => 'Malikite, chafiite, hanbalite';

  @override
  String get asrHanafi => 'Hanafite (plus tard)';

  @override
  String get adjustTimes => 'Ajuster les heures';

  @override
  String get adjustTimesNone => 'Telles que calculées';

  @override
  String adjustTimesSome(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count heures ajustées',
      one: '1 heure ajustée',
    );
    return '$_temp0';
  }

  @override
  String get adjustExplanation =>
      'Ajoutez ou retirez des minutes pour qu’une heure corresponde à celle de votre mosquée.';

  @override
  String offsetMinutes(String signed) {
    return '$signed min';
  }

  @override
  String semEarlier(String prayer) {
    return '$prayer : une minute plus tôt';
  }

  @override
  String semLater(String prayer) {
    return '$prayer : une minute plus tard';
  }

  @override
  String get prayerNote => 'Calculées sur votre téléphone. L’horaire d’une mosquée peut différer d’une minute ou deux.';

  @override
  String get noticeModelTitle => 'Le modèle vocal n’a pas pu démarrer';

  @override
  String get noticeModelBody =>
      'Rafiq reconnaît la récitation sur ce téléphone, et son modèle vocal ne s’est pas chargé. Fermez les autres applications et réessayez. Si cela se répète, redémarrez le téléphone.';

  @override
  String get noticeModelMissingTitle => 'Cette version n’a pas de modèle vocal';

  @override
  String get noticeModelMissingBody =>
      'Elle a été construite sans. Installez une version complète, ou faites la reconnaissance sur un ordinateur (Réglages → Développeur).';

  @override
  String warningFellBehind(String seconds) {
    return 'Le téléphone a pris du retard et a sauté $seconds s pour rattraper l’imam.';
  }

  @override
  String get introOffline =>
      'Tout se passe sur ce téléphone, sans internet. La récitation n’est jamais enregistrée ni envoyée.';

  @override
  String get useServer => 'Reconnaissance sur un ordinateur';

  @override
  String get useServerDetail =>
      'Pour le développement : le serveur de reconnaissance sur le même Wi-Fi, au lieu de ce téléphone';

  @override
  String get wordHighlight => 'Marquer le mot (expérimental)';

  @override
  String get wordHighlightDetail => 'En mode Tarawih, le mot récité est marqué quand le téléphone en est sûr';

  @override
  String get wordStale => 'Masquer le mot après';

  @override
  String wordStaleSeconds(String seconds) {
    return '$seconds s sans nouvelle reconnaissance';
  }

  @override
  String get duas => 'Douas';

  @override
  String get duasDetail => 'Pour le pardon, les soucis, le voyage, la maladie et plus';

  @override
  String duasCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count douas',
      one: '1 doua',
    );
    return '$_temp0';
  }

  @override
  String get duasNone => 'Aucune doua dans cette version de Rafiq.';

  @override
  String duaTimes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fois',
      one: 'une fois',
    );
    return '$_temp0';
  }

  @override
  String get groupData => 'Vos données';

  @override
  String get backupSave => 'Enregistrer une sauvegarde';

  @override
  String get backupSaveDetail =>
      'Signets, notes, khatm, historique de lecture et réglages, dans un fichier que vous gardez : avant de supprimer Rafiq, ou pour un nouveau téléphone';

  @override
  String get backupRestore => 'Restaurer une sauvegarde';

  @override
  String get backupRestoreDetail => 'À partir d’un fichier enregistré par Rafiq';

  @override
  String get backupSaved => 'Sauvegarde enregistrée';

  @override
  String get backupSaveFailed => 'La sauvegarde n’a pas pu être enregistrée. Essayez un autre emplacement.';

  @override
  String get backupOpenFailed => 'Ce fichier n’a pas pu être lu.';

  @override
  String get backupNotABackup => 'Ce fichier n’est pas une sauvegarde de Rafiq.';

  @override
  String get backupTooNew =>
      'Cette sauvegarde vient d’une version plus récente de Rafiq. Mettez Rafiq à jour, puis réessayez.';

  @override
  String backupRestoreAsk(String date) {
    return 'Restaurer la sauvegarde du $date ?';
  }

  @override
  String get backupRestoreWarning =>
      'Tout ce que Rafiq contient sur ce téléphone est remplacé par la sauvegarde : signets, notes, khatm, historique de lecture et réglages.';

  @override
  String get backupRestoreConfirm => 'Restaurer';

  @override
  String get backupRestored => 'Sauvegarde restaurée';
}
