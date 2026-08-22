#!/bin/bash
set -e

# [VIDEO - PARTE 2] extensions/ e um volume (para nao perder plugins instalados pelo
# Marketplace), mas isso congelaria o JAR do plugin na versao do primeiro boot.
# Solucao: o JAR mora em plugin-dist/ (dentro da imagem, fora do volume) e e reinstalado
# por cima do volume a cada start. Assim o upgrade e sempre a imagem que manda.
install -d "${SONARQUBE_HOME}/extensions/plugins"
install -m 0644 "${SONARQUBE_HOME}"/plugin-dist/*.jar "${SONARQUBE_HOME}/extensions/plugins/"

exec "${SONARQUBE_HOME}/docker/entrypoint.sh" "$@"
