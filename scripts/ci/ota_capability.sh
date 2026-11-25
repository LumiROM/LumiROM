#!/bin/bash
#
# Decides whether this run can publish signed OTA artifacts, and writes
# can_ota=true/false to $GITHUB_OUTPUT.
#
# Requires OTA_PK8, OTA_CERT and UPDATER_TOKEN (secrets). Set TEST_BUILD=true
# to force can_ota=false for a test run.

set -eo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set; run this from GitHub Actions}"

if [ -n "${OTA_PK8:-}" ] && [ -n "${OTA_CERT:-}" ] && [ -n "${UPDATER_TOKEN:-}" ] \
        && [ "${TEST_BUILD:-false}" != "true" ]; then
    echo "can_ota=true" >> "$GITHUB_OUTPUT"
else
    echo "can_ota=false" >> "$GITHUB_OUTPUT"
fi
