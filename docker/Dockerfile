FROM alpine:latest

LABEL maintainer="mero.mero.guero@gmail.com"
LABEL org.opencontainers.image.authors='mero.mero.guero@gmail.com'
LABEL org.opencontainers.image.url='https://github.com/mmguero/cleanvid'
LABEL org.opencontainers.image.source='https://github.com/mmguero/cleanvid'
LABEL org.opencontainers.image.title='ghcr.io/mmguero/cleanvid'
LABEL org.opencontainers.image.description='Containerized cleanvid'

ENV PYTHONUNBUFFERED 1

ADD . /usr/local/src/cleanvid

RUN apk add --update --no-cache py3-pip ttf-liberation && \
    python3 -m ensurepip && \
    python3 -m pip install --no-cache /usr/local/src/cleanvid && \
    rm -rf /usr/local/src/cleanvid
    
COPY --from=mwader/static-ffmpeg:6.0 /ffmpeg /usr/local/bin/
COPY --from=mwader/static-ffmpeg:6.0 /ffprobe /usr/local/bin/

ENTRYPOINT ["cleanvid"]
CMD []
