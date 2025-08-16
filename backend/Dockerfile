FROM python:3.12-slim AS builder
WORKDIR /app
COPY requirements.txt requirements.txt
RUN pip install --user -r requirements.txt

FROM python:3.12-slim
ENV PYTHONUNBUFFERED=1
WORKDIR /app
COPY --from=builder /root/.local /root/.local
ENV PATH=/root/.local/bin:$PATH
COPY . .
RUN mkdir -p /app/staticfiles /app/media && chown -R 1000:1000 /app/staticfiles /app/media
USER 1000:1000
CMD ["python","manage.py","runserver","0.0.0.0:8000"]
