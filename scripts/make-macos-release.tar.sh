#!/usr/bin/env sh
# shellcheck shell=dash
#
# A script to create Juvix release tars from Juvix homebrew bottles
#
# Example:
#   ./make-release-tar.sh juvix-0.4.2.arm64_ventura.bottle.tar.gz
#
# Output: juvix-macos-aarch64.tar.gz
#
# tar -tf juvix-macos-aarch64.tar.gz | tree --fromfile .
# .
# └── juvix
#
# Requirements:
#   GNU tar must be installed

main() {
    local _original_dir="$PWD"
    find_gnu_tar
    local _gnu_tar="$RETVAL"

    local _bottle="$1"
    assert_nz "$_bottle" "No bottle path provided"

    TMP=$(mktemp -d)
    trap 'rm -rf -- "$TMP"' EXIT
    cp "$_bottle" "$TMP"
    cd "$TMP" || exit

    "$_gnu_tar" -xf "$_bottle" --wildcards 'juvix/**/bin/juvix' --strip 3
    assert_file_exists "$TMP/juvix"
    find_arch "$TMP/juvix"
    local _juvix_arch="$RETVAL"
    local _juvix_output_filename="juvix-macos-$_juvix_arch.tar.gz"
    "$_gnu_tar" zcf "$_juvix_output_filename" juvix
    cp "$_juvix_output_filename" "$_original_dir"
}

say() {
    printf '%s\n' "$1"
}

err() {
    say "$1" >&2
    exit 1
}

check_gnu_tar() {
    need_cmd grep
    _tar_version=$($1 --version)
    echo "$_tar_version" | grep -q "GNU tar"
}

find_arch() {
    need_cmd file
    _juvix_file=$(file "$1")
    if echo "$_juvix_file" | grep -q "x86_64"; then
        RETVAL="x86_64"
    elif echo "$_juvix_file" | grep -q "arm64"; then
        RETVAL="aarch64"
    else
        err "Could not determine architecture of $_juvix_file"
    fi
}

find_gnu_tar() {
    need_cmd grep
    if check_gnu_tar "tar"; then
        RETVAL="tar"
    elif check_gnu_tar "gtar"; then
        RETVAL="gtar"
    else
        err "GNU tar is not installed"
    fi
}

need_cmd() {
    if ! check_cmd "$1"; then
        err "need '$1' (command not found)"
    fi
}

check_cmd() {
    command -v "$1" > /dev/null 2>&1
}

assert_nz() {
    if [ -z "$1" ]; then err "$2"; fi
}

assert_file_exists() {
    if [ ! -f "$1" ]; then err "expected $1 to exist"; fi
}

main "$@" || exit 1
