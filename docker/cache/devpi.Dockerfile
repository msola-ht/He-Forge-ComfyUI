FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DEVPI_SERVERDIR=/devpi/server

RUN python -m pip install --no-cache-dir --upgrade pip \
    && python -m pip install --no-cache-dir devpi-server devpi-web

RUN mkdir -p /devpi/server

EXPOSE 3141

CMD ["sh", "-c", "if [ ! -f \"$DEVPI_SERVERDIR/.serverversion\" ]; then devpi-init --serverdir \"$DEVPI_SERVERDIR\"; fi && devpi-server --host 0.0.0.0 --port 3141 --serverdir \"$DEVPI_SERVERDIR\""]
