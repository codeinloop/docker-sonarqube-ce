# syntax=docker/dockerfile:1

# [VIDEO - PARTE 2] A imagem oficial do SonarQube nao traz o Community Branch Plugin.
# Aqui montamos a imagem final em 2 estagios: baixar os artefatos + injetar na imagem oficial.
ARG SONARQUBE_VERSION=26.5.0.122743-community
ARG PLUGIN_VERSION=26.5.0

# --- Estagio 1: baixa o JAR do plugin e o webapp remendado -------------------
FROM alpine:3.23 AS downloader
ARG PLUGIN_VERSION
ARG DOWNLOAD_BASE_URL=https://github.com/mc1arke/sonarqube-community-branch-plugin/releases/download/${PLUGIN_VERSION}

ADD ${DOWNLOAD_BASE_URL}/sonarqube-community-branch-plugin-${PLUGIN_VERSION}.jar /tmp/sonarqube-community-branch-plugin.jar
ADD ${DOWNLOAD_BASE_URL}/sonarqube-webapp.zip /tmp/sonarqube-webapp.zip

RUN apk add --no-cache unzip \
 && mkdir -p /opt/sonarqube/web \
 && unzip -q /tmp/sonarqube-webapp.zip -d /opt/sonarqube/web

# --- Estagio 2: imagem final -------------------------------------------------
FROM sonarqube:${SONARQUBE_VERSION}

USER root
# O webapp original precisa ser substituido: e ele que renderiza as abas de branch/PR.
# plugin-dist/ e criado aqui de proposito: se nascer implicitamente do COPY abaixo, herda
# o --chmod=444 do arquivo e fica sem o bit de travessia, quebrando o boot.
RUN rm -rf /opt/sonarqube/web/*  && install -d -o sonarqube -g root -m 555 /opt/sonarqube/plugin-dist

# O JAR fica em plugin-dist/, fora de extensions/, para o volume nao mascara-lo.
COPY --from=downloader --chown=sonarqube:root --chmod=444 /tmp/sonarqube-community-branch-plugin.jar /opt/sonarqube/plugin-dist/sonarqube-community-branch-plugin.jar
COPY --from=downloader --chown=sonarqube:root --chmod=550 /opt/sonarqube/web /opt/sonarqube/web
COPY --chown=root:root --chmod=555 entrypoint.sh /opt/sonarqube/docker/entrypoint-branch-plugin.sh

USER sonarqube

# [VIDEO - PARTE 2] O plugin so funciona como javaagent, carregado nos dois processos
# da JVM do SonarQube: o WEB (interface/API) e o CE (Compute Engine, que processa a analise).
ENV SONAR_WEB_JAVAADDITIONALOPTS="-javaagent:/opt/sonarqube/extensions/plugins/sonarqube-community-branch-plugin.jar=web" \
    SONAR_CE_JAVAADDITIONALOPTS="-javaagent:/opt/sonarqube/extensions/plugins/sonarqube-community-branch-plugin.jar=ce"

ENTRYPOINT ["/opt/sonarqube/docker/entrypoint-branch-plugin.sh"]
