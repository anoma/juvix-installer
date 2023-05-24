#!/usr/bin/env sh
# shellcheck shell=dash

set -u

die() { echo "$*" >&2; exit 2; }

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
    while [ "$#" -gt 0 ]; do
        case $1 in
            --location)
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
    if ! [ "$EXPECTED_LOCATION" = "$_location" ]; then
        die "curl was passed location: $_location, expected $EXPECTED_LOCATION"
    fi
    cp "$STUB_TAR" "$_output"
}
