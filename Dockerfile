FROM alpine/helm:3.8.0

ENV HELM_CONFIG_HOME=/opt/helm
ENV HELM_REGISTRY_CONFIG=/opt/helm/registry.json
ENV HELM_REPOSITORY_CONFIG=/opt/helm/repositories.yaml
ENV HELM_REPOSITORY_CACHE=/opt/helm/cache/repository
ENV HELM_CACHE_HOME=/opt/helm/cache/helm
ENV HELM_DATA_HOME=/opt/helm/data
ENV HELM_PLUGINS=/opt/helm/plugins

RUN  apk add --no-cache bash curl jq \
  && apk add --no-cache -X http://dl-cdn.alpinelinux.org/alpine/edge/testing kubectl \
  && mkdir -p /opt/helm/plugins \
  && helm plugin install https://github.com/hypnoglow/helm-s3.git

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

CMD ["helm", "--help"]
