FROM python:3.12-slim

# System deps for rasterio/gdal and compilation
RUN apt-get update && apt-get install -y \
    build-essential gdal-bin libgdal-dev libproj-dev \
    && rm -rf /var/lib/apt/lists/*

# Install uv for faster package management
RUN pip install --no-cache-dir uv

ENV CPLUS_INCLUDE_PATH=/usr/include/gdal
ENV C_INCLUDE_PATH=/usr/include/gdal
ENV PYTHONUNBUFFERED=1

WORKDIR /app

COPY app/requirements.txt .
RUN uv pip install --system --no-cache -r requirements.txt

COPY ./app /app/app
COPY ./app/ingestion /app/ingestion

# Healthcheck and run
EXPOSE 8080
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080", "--proxy-headers"]