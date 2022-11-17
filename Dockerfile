# Copyright (c) 2022 MobileCoin Inc.
FROM alpine:edge

ENV HELM_CONFIG_HOME=/opt/helm
ENV HELM_REGISTRY_CONFIG=/opt/helm/registry.json
ENV HELM_REPOSITORY_CONFIG=/opt/helm/repositories.yaml
ENV HELM_REPOSITORY_CACHE=/opt/helm/cache/repository
ENV HELM_CACHE_HOME=/opt/helm/cache
ENV HELM_DATA_HOME=/opt/helm/data
ENV HELM_PLUGINS=/opt/helm/plugins

RUN  apk add --no-cache \
      --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing \
      bash curl jq kubectl helm git \
  && mkdir -p /opt/helm/plugins \
  && helm plugin install https://github.com/chartmuseum/helm-push

COPY entrypoint.sh /entrypoint.sh
COPY util /util

ENTRYPOINT ["/entrypoint.sh"]

CMD ["helm", "--help"]
