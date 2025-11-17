FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY app/ .

# Create non-root user
RUN useradd -m -u 1000 syncuser && \
    chown -R syncuser:syncuser /app

USER syncuser

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import requests; requests.get('http://localhost:5000/health')"

EXPOSE 5000

CMD ["python", "sync_service.py"]
