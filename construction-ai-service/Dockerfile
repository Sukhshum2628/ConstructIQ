FROM python:3.11-slim

# Install system dependencies needed by PyMuPDF, 
# pytesseract, and pdf2image
RUN apt-get update && apt-get install -y \
    libgl1-mesa-glx \
    libglib2.0-0 \
    libgomp1 \
    tesseract-ocr \
    poppler-utils \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy and install Python dependencies first
# (Docker layer cache — only rebuilds if requirements change)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the service
COPY . .

# Create directories that must exist at runtime
RUN mkdir -p chroma_db models data

# Railway injects PORT environment variable automatically
# Default to 8000 for local testing
ENV PORT=8000

EXPOSE $PORT

CMD uvicorn main:app --host 0.0.0.0 --port $PORT
