# Copyright (c) 2022 MobileCoin Inc.
FROM alpine:3.24.2

ENV HELM_CONFIG_HOME=/opt/helm
ENV HELM_REGISTRY_CONFIG=/opt/helm/registry.json
ENV HELM_REPOSITORY_CONFIG=/opt/helm/repositories.yaml
ENV HELM_REPOSITORY_CACHE=/opt/helm/cache/repository
ENV HELM_CACHE_HOME=/opt/helm/cache
ENV HELM_DATA_HOME=/opt/helm/data
ENV HELM_PLUGINS=/opt/helm/plugins

# hadolint ignore=DL3018 # ignore unpinned apk add
RUN apk add --no-cache \
      bash curl jq kubectl helm git

COPY entrypoint.sh /entrypoint.sh
COPY util /util

ENTRYPOINT ["/entrypoint.sh"]

CMD ["helm", "--help"]
