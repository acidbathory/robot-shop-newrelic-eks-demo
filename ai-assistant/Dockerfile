FROM python:3.12-slim

WORKDIR /app
ENV PYTHONUNBUFFERED=1 NEW_RELIC_CONFIG_FILE=/app/newrelic.ini

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py newrelic.ini ./
COPY static ./static

EXPOSE 8000
# newrelic-admin wraps uvicorn so the agent auto-instruments anthropic + FastAPI.
CMD ["newrelic-admin", "run-program", "uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
