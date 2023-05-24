#!/usr/bin/env sh
# shellcheck shell=dash

set -u

. stubs.sh

# Setup temp directory
BASE_TMP=$(mktemp -d)
trap 'rm -rf -- "$BASE_TMP"' EXIT

# common stub parameters
STUB_TAR=juvix.tar.gz

uname() {
    uname_stub "$@"
}

curl() {
    curl_stub "$@"
}

run_assertion_ok() {
    XDG_DATA_HOME=$(mktemp -d "$BASE_TMP"/data.XXXXX)
    XDG_BIN_HOME=$(mktemp -d "$BASE_TMP"/bin.XXXXX)

    . ../juvix-installer.sh
    if [ ! -f "$XDG_BIN_HOME"/juvix ]; then
        die "juvix binary was not copied to the output"
    fi

    if [ ! -f "$XDG_DATA_HOME"/juvix/env ]; then
        die "juvix env file was not copied to the output"
    fi

    local _cmd_output
    _cmd_output=$("$XDG_BIN_HOME"/juvix)

    if ! [ "$_cmd_output" = "Hello from Juvix" ]; then
        die "juvix binary did not produce expected output"
    fi
}

expected_location() {
    printf "https://github.com/anoma/juvix/releases/latest/download/juvix-%s-%s.tar.gz" "$1" "$2"
}

# Test: OS=Dawrin,arch=arm64,curl
STUB_UNAME_M=arm64
STUB_UNAME_S=Darwin
EXPECTED_LOCATION=$(expected_location 'macos' 'aarch64')
JUVIX_INSTALLER_NONINTERACTIVE=1
run_assertion_ok

# Test: OS=Dawrin,arch=x86_64,curl
STUB_UNAME_M=x86_64
STUB_UNAME_S=Darwin
EXPECTED_LOCATION=$(expected_location 'macos' 'x86_64')
JUVIX_INSTALLER_NONINTERACTIVE=1
run_assertion_ok

# Test: OS=Linux,arch=x86_64,curl
STUB_UNAME_M=x86_64
STUB_UNAME_S=Linux
EXPECTED_LOCATION=$(expected_location 'linux' 'x86_64')
JUVIX_INSTALLER_NONINTERACTIVE=1
run_assertion_ok

# Test: OS=Linux,arch=amd64,curl
STUB_UNAME_M=amd64
STUB_UNAME_S=Linux
EXPECTED_LOCATION=$(expected_location 'linux' 'x86_64')
JUVIX_INSTALLER_NONINTERACTIVE=1
run_assertion_ok
