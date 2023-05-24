#!/usr/bin/env sh
# shellcheck shell=dash
#
# Adapted from https://github.com/rust-lang/rustup/blob/6242769391e033cd751831a17c24bc00ccde0204/rustup-init.sh

set -u

JUVIX_RELEASE_ROOT="${JUVIX_RELEASE_ROOT:-https://github.com/anoma/juvix/releases}"

JUVIX_DIR=${XDG_DATA_HOME:=$HOME/.local/share}/juvix
JUVIX_BIN=${XDG_BIN_HOME:=$HOME/.local/bin}
JUVIX_INSTALLER_NONINTERACTIVE=${JUVIX_INSTALLER_NONINTERACTIVE:=0}

usage() {
    cat <<EOF
juvix-installer 0.1.0

USAGE:
    juvix-installer
EOF
}

main() {
    downloader --check
    get_architecture
    need_cmd uname
    need_cmd mktemp
    need_cmd mkdir
    need_cmd rm
    need_cmd rmdir
    need_cmd tar

    get_architecture || return 1
    local _arch="$RETVAL"
    assert_nz "$_arch" "arch"

    local _dir
    if ! _dir="$(ensure mktemp -d)"; then
        exit 1
    fi
    local _filename="juvix-${_arch}.tar.gz"
    local _file="${_dir}/${_filename}"
    local _url="${JUVIX_RELEASE_ROOT}/latest/download/${_filename}"

    find_shell_name
    local _shell_name="$RETVAL"
    find_profile_path
    local _profile_path="$RETVAL"

    ask_profile "$_shell_name" "$_profile_path"
    local _adjust_profile_answer="$RETVAL"

    write_env

    printf '%s\n' 'info: downloading juvix' 1>&2
    ensure mkdir -p "$_dir"
    ensure downloader "$_url" "$_file" "$_arch"

    printf '%s\n' "info: copying juvix into ${JUVIX_BIN}" 1>&2
    ensure mkdir -p "${JUVIX_BIN}"
    ensure tar -xzf "$_file" -C "${JUVIX_BIN}"
    ignore rm "$_file"
    ignore rmdir "$_dir"

    adjust_profile "$_adjust_profile_answer" "$_shell_name" "$_profile_path"
}


# Writes a script to $JUVIX_DIR/env that, when sourced, prepends the
# ${JUVIX_BIN} directory to $PATH if it is not already present there.
write_env() {
    ensure mkdir -p "${JUVIX_DIR}"
    local _env_file="${JUVIX_DIR}/env"
    cat <<-EOF > "$_env_file" || err "Failed to create env file: $_env_file"
case ":\$PATH:" in
    *:"${JUVIX_BIN}":*)
        ;;
    *)
        export PATH="${JUVIX_BIN}:\$PATH"
        ;;
esac
EOF
}

get_architecture() {
    local _osttype
    local _cputype
    local _arch
    _ostype="$(uname -s)"
    _cputype="$(uname -m)"

    case "$_ostype" in

        Linux)
            _ostype=linux
            ;;

        Darwin)
            _ostype=macos
            ;;

        *)
            err "unsupported OS: $_ostype"
            ;;

    esac

    case "$_cputype" in
        x86_64 | x86-64 | x64 | amd64)
            _cputype=x86_64
            ;;

        aarch64 | arm64)
            _cputype=aarch64
            ;;

        *)
            err "unsupported CPU: $_cputype"
    esac

    if [ "$_ostype" = linux ] && [ "$_cputype" = aarch64 ]; then
        err "linux-aarch64 is not supported"
    fi

    _arch="${_ostype}-${_cputype}"

    RETVAL="$_arch"
}

say() {
    printf 'juvix-installer: %s\n' "$1"
}

err() {
    say "$1" >&2
    exit 1
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
    if [ -z "$1" ]; then err "assert_nz $2"; fi
}

# Run a command that should never fail. If the command fails execution
# will immediately terminate with an error showing the failing
# command.
ensure() {
    if ! "$@"; then err "command failed: $*"; fi
}

# This is just for indicating that commands' results are being
# intentionally ignored. Usually, because it's being executed
# as part of error handling.
ignore() {
    "$@"
}

# This wraps curl or wget. Try curl first, if not installed,
# use wget instead.
downloader() {
    local _dld
    local _err
    local _status
    if check_cmd curl; then
        _dld=curl
    elif check_cmd wget; then
        _dld=wget
    else
        _dld='curl or wget' # to be used in error message of need_cmd
    fi

    if [ "$1" = --check ]; then
        need_cmd "$_dld"
    elif [ "$_dld" = curl ]; then
        _err=$(curl --proto '=https' --tlsv1.2 --silent --show-error --fail --location "$1" --output "$2" 2>&1)
        _status=$?
        if [ -n "$_err" ]; then
            echo "$_err" >&2
            if echo "$_err" | grep -q 404$; then
                err "installer for platform '$3' not found, this may be unsupported"
            fi
        fi
        return $_status
    elif [ "$_dld" = wget ]; then
        _err=$(wget --https-only --secure-protocol=TLSv1_2 "$1" -O "$2" 2>&1)
        _status=$?
        if [ -n "$_err" ]; then
            echo "$_err" >&2
            if echo "$_err" | grep -q ' 404 Not Found$'; then
                err "installer for platform '$3' not found, this may be unsupported"
            fi
        fi
        return $_status
    else
        err "Unknown downloader"
    fi
}

find_shell_name() {
    local _shell_name
    case ${SHELL:=""} in
        */zsh)
            _shell_name="zsh" ;;
        */bash)
            _shell_name="bash" ;;
        */sh) # login shell is sh, but might be a symlink to bash or zsh
            if [ -n "${BASH:-}" ] ; then
                _shell_name="bash"
            elif [ -n "${ZSH_VERSION:-}" ] ; then
                _shell_name="zsh"
            else
                _shell_name=""
            fi
            ;;
        */fish)
            _shell_name="fish" ;;
        *)
            _shell_name="" ;;
    esac
    RETVAL="$_shell_name"
}

find_profile_path() {
    local _profile_path
    case $SHELL in
        */zsh)
            if [ -n "${ZDOTDIR:-}" ]; then
                _profile_file="$ZDOTDIR/.zshrc"
            else
                _profile_file="$HOME/.zshrc"
            fi ;;
        */bash)
            _profile_file="$HOME/.bashrc" ;;
        */sh)
            if [ -n "${BASH:-}" ] ; then
                _profile_file="$HOME/.bashrc"
            elif [ -n "${ZSH_VERSION:-}" ] ; then
                _profile_file="$HOME/.zshrc"
            else
                _profile_file=""
            fi
            ;;
        */fish)
            _profile_file="$HOME/.config/fish/config.fish" ;;
        *) _profile_file="" ;;
    esac
    RETVAL="$_profile_file"
}

# Ask user if they want to adjust the shell profile.
ask_profile() {
    local _shell_name=$1
    local _profile_path=$2
    if [ -z "$_shell_name" ] ; then
        RETVAL="noop"
        return
    fi

    local _profile_answer
    local _profile_action

    if [ -z "${JUVIX_INSTALLER_NONINTERACTIVE}" ]; then
        while true; do
                echo "-------------------------------------------------------------------------------"
                echo ""
                echo "Detected $_shell_name shell on your system..."
                echo "Do you want to automatically prepend the required PATH variable to \"${_profile_file}\"?"
                echo ""
                echo "[Y] Yes  [N] No  [?] Help (default is \"Y\")."
                echo ""
                read -r _profile_answer </dev/tty
            case $_profile_answer in
                [Yy]* | "")
                    _profile_action="adjust"
                    break
                    ;;
                [Nn]*)
                    _profile_action="noop"
                    break
                    ;;

                *)
                    ;;
            esac
        done
    else
        _profile_action="noop"
    fi
    RETVAL="$_profile_action"
}

# Adjust the user profile to prepend the JUVIX_BIN to the PATH
adjust_profile() {
    local _profile_action=$1
    local _shell_name=$2
    local _profile_path=$3

    case "$_profile_action" in
        adjust)
            case "$_shell_name" in
                "")
                    warn_path "Couldn't figure out login shell!"
                    return
                    ;;
                fish)
                    mkdir -p "${_profile_path%/*}"
                    sed -i -e '/# juvix-env$/ s/^#*/#/' "${_profile_path}"
                    printf "\n%s" "set -gx PATH $JUVIX_BIN \$PATH # juvix-env" >> "${_profile_path}"
                    ;;
                bash)
                    sed -i -e '/# juvix-env$/ s/^#*/#/' "${_profile_path}"
                    printf "\n%s" "[ -f \"${JUVIX_DIR}/env\" ] && source \"${JUVIX_DIR}/env\" # juvix-env" >> "${_profile_path}"
                    ;;

                zsh)
                    sed -i -e '/# juvix-env$/ s/^#*/#/' "${_profile_path}"
                    printf "\n%s" "[ -f \"${JUVIX_DIR}/env\" ] && source \"${JUVIX_DIR}/env\" # juvix-env" >> "${_profile_path}"
                    ;;
            esac
            echo
            echo "==============================================================================="
            echo
            echo "OK! ${_profile_path} has been modified. Restart your terminal for the changes to take effect,"
            echo "or type \"source ${JUVIX_DIR}/env\" to apply them in your current terminal session."
            return
            ;;
        *)
            warn_path ""
            ;;
    esac
}

warn_path() {
    local _msg=$1
    echo
    echo "==============================================================================="
    echo "$_msg"
    echo "In order to run juvix, you need to adjust your PATH variable."
    echo "To do so, you may want to run 'source $JUVIX_DIR/env' in your current terminal"
    echo "session as well as your shell configuration (e.g. ~/.bashrc)."
}


main "$@" || exit 1
