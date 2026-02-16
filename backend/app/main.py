from fastapi import FastAPI
from app.services.quran_service import QuranService

app = FastAPI()

# Load Quran once when server starts
quran_service = QuranService()

@app.get("/")
def root():
    return {"message": "Quran API is running"}

@app.get("/search")
def search(q: str):
    result = quran_service.find_by_text(q)
    if result:
        return result
    return {"message": "No verse found"}
