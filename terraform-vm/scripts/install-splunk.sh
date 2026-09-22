#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="/var/log/splunk-install.log"

exec > >(tee -a "${LOG_FILE}") 2>&1

echo "=== Splunk provisioning started: $(date -Is) ==="

touch /var/tmp/splunk-provisioning-test

echo "Splunk provisioning test completed successfully."
echo "=== Splunk provisioning finished: $(date -Is) ==="
