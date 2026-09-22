#!/usr/bin/env bash

set -euo pipefail

SPLUNK_VERSION="10.4.3"
SPLUNK_BUILD="4174a2deda5d"
SPLUNK_PACKAGE="splunk-${SPLUNK_VERSION}-${SPLUNK_BUILD}-linux-amd64.deb"
SPLUNK_URL="https://download.splunk.com/products/splunk/releases/${SPLUNK_VERSION}/linux/${SPLUNK_PACKAGE}"

SPLUNK_HOME="/opt/splunk"

echo "==> Installing Splunk Enterprise ${SPLUNK_VERSION}"

# Do not overwrite or upgrade an existing Splunk installation.
if [[ -x "${SPLUNK_HOME}/bin/splunk" ]]; then
    echo "==> Existing Splunk installation detected at ${SPLUNK_HOME}"
    echo "==> Skipping installation"
    exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

cd "${TMP_DIR}"

echo "==> Downloading ${SPLUNK_PACKAGE}"

curl \
    --fail \
    --location \
    --retry 3 \
    --output "${SPLUNK_PACKAGE}" \
    "${SPLUNK_URL}"

echo "==> Installing ${SPLUNK_PACKAGE}"

DEBIAN_FRONTEND=noninteractive \
    dpkg -i "${SPLUNK_PACKAGE}"

if [[ ! -x "${SPLUNK_HOME}/bin/splunk" ]]; then
    echo "ERROR: Splunk installation failed"
    exit 1
fi

echo "==> Splunk Enterprise installed successfully"

echo "==> Starting Splunk Enterprise"

sudo -u splunk "${SPLUNK_HOME}/bin/splunk" start \
    --accept-license \
    --answer-yes \
    --no-prompt \
    --gen-and-print-passwd

echo "==> Stopping Splunk Enterprise before configuring systemd"

sudo -u splunk "${SPLUNK_HOME}/bin/splunk" stop

echo "==> Configuring Splunk to start with systemd"

"${SPLUNK_HOME}/bin/splunk" enable boot-start \
    --accept-license \
    -systemd-managed 1 \
    -user splunk \
    -group splunk

echo "==> Starting Splunk Enterprise with systemd"

systemctl start Splunkd.service

echo "==> Splunk Enterprise provisioning complete"
