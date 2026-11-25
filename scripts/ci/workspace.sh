#!/bin/bash
#
# Creates the build directories, seeds makerom/ from template/ and makes the
# bundled tools executable.

set -eo pipefail

bash scripts/utils/setup_directories.sh FIRMWARE WORK OUT ROM TMP IMGs TARGET_FILES

find scripts -name "*.sh" -exec chmod +x {} +
chmod +x bin/MergeOTA/MergeAll.sh
chmod +x bin/erofs-utils/extract.erofs
chmod +x bin/erofs-utils/mkfs.erofs
chmod +x bin/lp/*
