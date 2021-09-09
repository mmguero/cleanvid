FROM alpine:latest

LABEL maintainer="mero.mero.guero@gmail.com"
LABEL org.opencontainers.image.authors='mero.mero.guero@gmail.com'
LABEL org.opencontainers.image.url='https://github.com/mmguero/cleanvid'
LABEL org.opencontainers.image.source='https://github.com/mmguero/cleanvid'
LABEL org.opencontainers.image.title='mmguero/cleanvid'
LABEL org.opencontainers.image.description='Dockerized cleanvid'

ENV PYTHONUNBUFFERED 1

ADD requirements.txt /tmp/requirements.txt

RUN apk add --update --no-cache py3-pip && \
    python3 -m ensurepip && \
    python3 -m pip install --no-cache --upgrade -r /tmp/requirements.txt && \
    rm -f /tmp/requirements.txt

COPY --from=mwader/static-ffmpeg:latest /ffmpeg /usr/local/bin/
COPY --from=mwader/static-ffmpeg:latest /qt-faststart /usr/local/bin/

ADD *.py /usr/local/bin/
ADD swears.txt /usr/local/bin

ENTRYPOINT ["python3", "/usr/local/bin/cleanvid.py"]
CMD []
