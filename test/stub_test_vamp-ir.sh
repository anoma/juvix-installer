#!/usr/bin/env sh
# shellcheck shell=dash

set -u

# Setup temp directory
BASE_TMP=$(mktemp -d)
trap 'rm -rf -- "$BASE_TMP"' EXIT

# common stub parameters
STUB_VAMPIR_TAR=vamp-ir.tar.gz

die() { echo "Test FAIL: $*" >&2; exit 2; }

uname_stub() {
    for arg in "$@"; do
        OPTIND=1
        while getopts :sm sub_arg "$arg"; do
            case "$sub_arg" in
                m)
                    echo "$STUB_UNAME_M"
                    exit 0
                    ;;
                s)
                    echo "$STUB_UNAME_S"
                    exit 0
                    ;;
                *)
                    ;;
            esac
        done
    done
}

curl_stub() {
    local _output
    local _location
    local _expected_location
    local _stub_tar
    while [ "$#" -gt 0 ]; do
        case $1 in
            --location)
                case $2 in
                    *vamp-ir*)
                        _expected_location="$EXPECTED_VAMPIR_LOCATION"
                        _stub_tar="$STUB_VAMPIR_TAR"
                        ;;
                    *)
                        ;;
                esac
                _location="$2"
                shift
                shift
                ;;
            --output)
                _output="$2"
                shift
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    if [ -z "$_output" ]; then die "curl_stub: output missing"; fi
    if [ -z "$_location" ]; then die "curl_stub: location missing"; fi
    if ! [ "$_expected_location" = "$_location" ]; then
        die "curl was passed location: $_location, expected $_expected_location"
    fi
    cp "$_stub_tar" "$_output"
}

wget_stub() {
    local _output
    local _location
    local _expected_location
    local _stub_tar
    while [ "$#" -gt 0 ]; do
        case $1 in
            -O)
                _output="$2"
                shift
                shift
                ;;
            --*|-*)
                shift
                shift
                ;;
            *)
                case $1 in
                    *vamp-ir*)
                        _expected_location="$EXPECTED_VAMPIR_LOCATION"
                        _stub_tar="$STUB_VAMPIR_TAR"
                        ;;
                    *)
                        ;;
                esac
                _location="$1"
                shift
                ;;
        esac
    done
    if [ -z "$_output" ]; then die "wget_stub: output missing"; fi
    if [ -z "$_location" ]; then die "wget_stub: location missing"; fi
    if ! [ "$_expected_location" = "$_location" ]; then
        die "wget was passed location: $_location, expected $_expected_location"
    fi
    cp "$_stub_tar" "$_output"
}

command_stub_no_curl() {
    while [ "$#" -gt 0 ]; do
        case $1 in
            curl)
                return 1
                ;;
            *)
                shift
                ;;
        esac
    done
}

uname() {
    uname_stub "$@"
}

curl() {
    curl_stub "$@"
}

wget() {
    wget_stub "$@"
}

run_assertion_ok() {
    XDG_DATA_HOME=$(mktemp -d "$BASE_TMP"/data.XXXXX)
    XDG_BIN_HOME=$(mktemp -d "$BASE_TMP"/bin.XXXXX)

    . ../vamp-ir-installer.sh
    if [ ! -f "$XDG_BIN_HOME"/vamp-ir ]; then
        die "vamp-ir binary was not copied to the output"
    fi

    if [ ! -f "$XDG_DATA_HOME"/vamp-ir/env ]; then
        die "vamp-ir env file was not copied to the output"
    fi

    if [ ! -f "$XDG_DATA_HOME"/vamp-ir/env.fish ]; then
        die "vamp-ir env.fish file was not copied to the output"
    fi

    local _vampir_cmd_output
    _vampir_cmd_output=$("$XDG_BIN_HOME"/vamp-ir)
    if ! [ "$_vampir_cmd_output" = "Hello from vamp-ir" ]; then
        die "vamp-ir binary did not produce expected output"
    fi

    if ! fish -c "set -e PATH; set -x PATH /usr/bin /bin; source $XDG_DATA_HOME/vamp-ir/env.fish; vamp-ir" >/dev/null 2>&1 ; then
        die "sourcing fish environment failed"
    fi

    if ! zsh -c "unset PATH; export PATH='/usr/bin:/bin'; source $XDG_DATA_HOME/vamp-ir/env; vamp-ir" >/dev/null 2>&1 ; then
        die "sourcing zsh environment failed"
    fi

    if ! bash -c "unset PATH; export PATH='/usr/bin:/bin'; source $XDG_DATA_HOME/vamp-ir/env; vamp-ir" >/dev/null 2>&1 ; then
        die "sourcing zsh environment failed"
    fi
}

expected_vampir_location() {
    printf "https://github.com/anoma/vamp-ir/releases/latest/download/vamp-ir-%s-%s.tar.gz" "$2" "$1"
}

echo "Test: OS=Dawrin,arch=arm64,curl"
STUB_UNAME_M=arm64
STUB_UNAME_S=Darwin
EXPECTED_VAMPIR_LOCATION=$(expected_vampir_location 'apple-darwin' 'aarch64')
VAMPIR_INSTALLER_NONINTERACTIVE=1
SHELL=/bin/bash
run_assertion_ok

echo "Test: OS=Dawrin,arch=x86_64,curl"
STUB_UNAME_M=x86_64
STUB_UNAME_S=Darwin
EXPECTED_VAMPIR_LOCATION=$(expected_vampir_location 'apple-darwin' 'x86_64')
VAMPIR_INSTALLER_NONINTERACTIVE=1
SHELL=/bin/bash
run_assertion_ok

echo "Test: OS=Linux,arch=x86_64,curl"
STUB_UNAME_M=x86_64
STUB_UNAME_S=Linux
EXPECTED_VAMPIR_LOCATION=$(expected_vampir_location 'unknown-linux-musl' 'x86_64')
VAMPIR_INSTALLER_NONINTERACTIVE=1
SHELL=/bin/bash
run_assertion_ok

echo "Test: OS=Linux,arch=amd64,curl"
STUB_UNAME_M=amd64
STUB_UNAME_S=Linux
EXPECTED_VAMPIR_LOCATION=$(expected_vampir_location 'unknown-linux-musl' 'x86_64')
VAMPIR_INSTALLER_NONINTERACTIVE=1
unset SHELL
run_assertion_ok

echo "Test: wget is called if curl is not available"
command() {
    command_stub_no_curl "$@"
}

unset curl

curl() {
    die "I shouldn't be called"
}

STUB_UNAME_M=arm64
STUB_UNAME_S=Darwin
EXPECTED_VAMPIR_LOCATION=$(expected_vampir_location 'apple-darwin' 'aarch64')
VAMPIR_INSTALLER_NONINTERACTIVE=1
SHELL=/bin/bash
run_assertion_ok
