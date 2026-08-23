#!/bin/bash
set -e

install -d "${SONARQUBE_HOME}/extensions/plugins"
install -m 0644 "${SONARQUBE_HOME}"/plugin-dist/*.jar "${SONARQUBE_HOME}/extensions/plugins/"

exec "${SONARQUBE_HOME}/docker/entrypoint.sh" "$@"
