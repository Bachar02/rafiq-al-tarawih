/// Display-time preparation of Quran text (Rubric brand book §4).
///
/// `quran.json` is never changed. At display time only, two ordinary spaces
/// become no-break spaces (U+00A0), so a line can no longer break before an
/// ayah-end marker or a standalone pause mark. No letter, mark or order of
/// the text changes and the rendering is identical; only where a line may
/// break changes. Measured over the whole Quran at 16 width/scale
/// combinations: stranded markers and pause marks go from hundreds to zero.
library;

const nbsp = ' ';

/// ۝ — the ayah-end sign. Followed by Arabic-Indic digits, Amiri Quran
/// shapes it into one enclosed marker (۝١ .. ۝٢٨٦).
const ayahEndSign = '۝';

/// The single ordinary space before a standalone pause mark (U+06D6–U+06DC),
/// e.g. the one in `رَيْبَ ۛ فِيهِ`.
final _spaceBeforePauseMark = RegExp(' (?=[ۖ-ۜ])');

/// 29 -> ٢٩. Quran ayah markers keep Arabic-Indic digits in every language.
String arabicDigits(int n) => n.toString().split('').map((d) => String.fromCharCode(0x0660 + int.parse(d))).join();

/// The enclosed ayah-end marker for [ayah], e.g. ۝٣.
String ayahEndMarker(int ayah) => '$ayahEndSign${arabicDigits(ayah)}';

/// [uthmani] with the space before each standalone pause mark made unbreakable.
String preparePauseMarks(String uthmani) => uthmani.replaceAll(_spaceBeforePauseMark, nbsp);

/// The ayah's text as displayed, without its end marker: [preparePauseMarks]
/// plus the no-break space that joins the text to [ayahEndMarker].
String displayAyahText(String uthmani) => '${preparePauseMarks(uthmani)}$nbsp';
