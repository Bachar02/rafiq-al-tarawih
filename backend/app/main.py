from fastapi import FastAPI
from app.services.quran_service import QuranService

app = FastAPI()

# Load Quran once when server starts
quran_service = QuranService()

@app.get("/")
def root():
    return {"message": "Quran API is running"}

@app.get("/search")
def search(q: str, limit: int = 10):
    """
    Search for verses similar to the query text.
    
    Args:
        q: The search query text
        limit: Maximum number of verses to return (default: 10)
    
    Returns:
        A list of similar verses (up to the limit)
    """
    results = quran_service.find_similar_verses(q, limit=limit)
    if results:
        return {"verses": results, "count": len(results)}
    return {"message": "No verses found", "verses": [], "count": 0}
