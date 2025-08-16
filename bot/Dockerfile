FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt requirements.txt
RUN pip install --user -r requirements.txt
COPY . .
USER 1000:1000
CMD ["python","-m","bot.worker.main"]
