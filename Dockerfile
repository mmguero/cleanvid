FROM linuxserver/ffmpeg:latest

LABEL maintainer="mero.mero.guero@gmail.com"
LABEL org.opencontainers.image.authors='mero.mero.guero@gmail.com'
LABEL org.opencontainers.image.url='https://github.com/mmguero/cleanvid'
LABEL org.opencontainers.image.source='https://github.com/mmguero/cleanvid'
LABEL org.opencontainers.image.title='mmguero/cleanvid'
LABEL org.opencontainers.image.description='Dockerized cleanvid'

ENV DEBIAN_FRONTEND noninteractive
ENV TERM xterm

ADD requirements.txt /tmp/requirements.txt

RUN apt-get update -q && \
    apt-get -y install -qq --no-install-recommends \
      build-essential \
      python3-dev \
      python3-setuptools \
      python3-pip && \
    python3 -m pip install --no-cache-dir -r /tmp/requirements.txt && \
    apt-get -q -y --purge remove build-essential python3-dev && \
    apt-get -y -q --allow-downgrades --allow-remove-essential --allow-change-held-packages autoremove && \
    apt-get clean && \
      rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/cache/*/*

ADD *.py /usr/local/bin/
ADD swears.txt /usr/local/bin

ENTRYPOINT ["python3", "/usr/local/bin/cleanvid.py"]
CMD []
