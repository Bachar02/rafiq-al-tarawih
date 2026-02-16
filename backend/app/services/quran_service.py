from pathlib import Path

class QuranService:
    def __init__(self):
        # Go up to project root
        base_dir = Path(__file__).resolve() \
            .parent   # services
        base_dir = base_dir.parent  # app
        base_dir = base_dir.parent  # backend
        base_dir = base_dir.parent  # quran_app (project root)

        quran_path = base_dir / "data" / "quran" / "quran.txt"

        self.verses = []
        self._load_quran(quran_path)

    def _load_quran(self, path: Path):
        if not path.exists():
            raise FileNotFoundError(f"Quran file not found at {path}")

        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue  # skip empty lines
                if line.startswith("#"):
                    continue  # skip comment lines

                parts = line.split("|")
                if len(parts) != 3:
                    continue  # skip malformed lines silently

                surah_str, ayah_str, text = parts
                try:
                    surah = int(surah_str)
                    ayah = int(ayah_str)
                except ValueError:
                    continue  # skip lines with invalid numbers

                self.verses.append({
                    "surah": surah,
                    "ayah": ayah,
                    "text": text
                })


    def find_by_text(self, query: str):
        for verse in self.verses:
            if query.strip() in verse["text"]:
                return verse
        return None

    def find_similar_verses(self, query: str, limit: int = 10):
        """
        Find verses similar to the query text.
        
        Args:
            query: The search text
            limit: Maximum number of verses to return (default: 10)
            
        Returns:
            A list of similar verses (up to the limit)
        """
        query = query.strip()
        if not query:
            return []
        
        similar_verses = []
        for verse in self.verses:
            if query in verse["text"]:
                similar_verses.append(verse)
                
        return similar_verses[:limit]


# 🔥 Minimal test
if __name__ == "__main__":
    service = QuranService()
    result = service.find_by_text("الحمد لله رب العالمين")
    print(result)
