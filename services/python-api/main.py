# python service: python-api
from fastapi import FastAPI
import uvicorn
import os

app = FastAPI(title="python-api", description="python service")

@app.get("/")
async def root():
    return {
        "message": "Hello from python-api!",
        "service": "python-api",
        "type": "python",
        "runtime": "python3"
    }

@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "service": "python-api",
        "type": "python"
    }

if __name__ == "__main__":
    port = int(os.getenv("PORT", 8000))
    host = os.getenv("HOST", "0.0.0.0")
    uvicorn.run(app, host=host, port=port)
