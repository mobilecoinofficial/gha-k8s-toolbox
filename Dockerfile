# Copyright (c) 2022 MobileCoin Inc.
FROM ubuntu:20.04

ENV HELM_CONFIG_HOME=/opt/helm
ENV HELM_REGISTRY_CONFIG=/opt/helm/registry.json
ENV HELM_REPOSITORY_CONFIG=/opt/helm/repositories.yaml
ENV HELM_REPOSITORY_CACHE=/opt/helm/cache/repository
ENV HELM_CACHE_HOME=/opt/helm/cache
ENV HELM_DATA_HOME=/opt/helm/data
ENV HELM_PLUGINS=/opt/helm/plugins


RUN  apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y \
      apt-transport-https \
      ca-certificates \
      curl \
      git \
      jq \
  && curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg -o /usr/share/keyrings/kubernetes-archive-keyring.gpg \
  && echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list \
  && apt-get update \
  && apt-get install -y kubectl \
  && apt-get clean \
  && rm -r /var/lib/apt/lists

RUN curl -fsSL https://get.helm.sh/helm-v3.10.2-linux-amd64.tar.gz -o /tmp/helm-linux-amd64.tar.gz \
  && tar --strip-components 1 -xvzf /tmp/helm-linux-amd64.tar.gz -C /usr/local/bin linux-amd64/helm \
  && rm /tmp/helm-linux-amd64.tar.gz \
  && mkdir -p /opt/helm/plugins \
  && helm plugin install https://github.com/chartmuseum/helm-push

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

CMD ["helm", "--help"]
