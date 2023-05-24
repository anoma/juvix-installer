#!/usr/bin/env sh

set -u

die() { echo "$*" >&2; exit 2; }

# Setup temp directory
BASE_TMP=$(mktemp -d)
trap 'rm -rf -- "$BASE_TMP"' EXIT

export XDG_DATA_HOME=$(mktemp -d "$BASE_TMP"/data.XXXXX)
export XDG_BIN_HOME=$(mktemp -d "$BASE_TMP"/bin.XXXXX)
export JUVIX_INSTALLER_NONINTERACTIVE=1

../juvix-installer.sh

if [ ! -f "$XDG_BIN_HOME"/juvix ]; then
    die "juvix binary was not copied to the output"
fi

if [ ! -f "$XDG_DATA_HOME"/juvix/env ]; then
    die "juvix env file was not copied to the output"
fi

if ! "$XDG_BIN_HOME"/juvix --help; then
    die "juvix binary at $XDG_BIN_HOME/juvix returned non-zero exit code"
fi
