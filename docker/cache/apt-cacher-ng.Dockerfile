FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends apt-cacher-ng ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/cache/apt-cacher-ng /var/log/apt-cacher-ng \
    && chown -R apt-cacher-ng:apt-cacher-ng /var/cache/apt-cacher-ng /var/log/apt-cacher-ng

EXPOSE 3142

CMD ["apt-cacher-ng", "ForeGround=1"]
