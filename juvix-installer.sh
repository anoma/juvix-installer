#!/usr/bin/env sh
# shellcheck shell=dash
#
# Adapted from https://github.com/rust-lang/rustup/blob/6242769391e033cd751831a17c24bc00ccde0204/rustup-init.sh

set -u

JUVIX_RELEASE_ROOT="${JUVIX_RELEASE_ROOT:-https://github.com/anoma/juvix/releases}"

JUVIX_DIR=${XDG_DATA_HOME:=$HOME/.local/share}/juvix
JUVIX_BIN=${XDG_BIN_HOME:=$HOME/.local/bin}
JUVIX_INSTALLER_NONINTERACTIVE=${JUVIX_INSTALLER_NONINTERACTIVE:-}
JUVIX_INSTALLER_ASSUME_YES=${JUVIX_INSTALLER_ASSUME_YES:-}

usage() {
    cat <<EOF
juvix-installer 0.2.0

USAGE:
    juvix-installer [OPTIONS]

OPTIONS:
    -y
            Answer "yes" to any prompts. Proceeding with all operations if they are possible.

    -h, --help
            Print help information
EOF
}

main() {
    downloader --check
    need_cmd uname
    need_cmd mktemp
    need_cmd mkdir
    need_cmd rm
    need_cmd rmdir
    need_cmd tar

    get_juvix_architecture || return 1
    local _juvix_arch="$RETVAL"
    assert_nz "$_juvix_arch" "_juvix_arch"

    get_llvmbox_architecture || return 1
    local _llvmbox_arch="$RETVAL"
    assert_nz "$_llvmbox_arch" "_llvmbox_arch"

    local _dir
    if ! _dir="$(ensure mktemp -d)"; then
        exit 1
    fi
    local _juvix_filename="juvix-${_juvix_arch}.tar.gz"
    local _juvix_file="${_dir}/${_juvix_filename}"
    local _juvix_url="${JUVIX_RELEASE_ROOT}/latest/download/${_juvix_filename}"

    local _llvmbox_version="15.0.7%2B3"
    local _llvmbox_filename="llvmbox-${_llvmbox_version}-${_llvmbox_arch}.tar.xz"
    local _llvmbox_file="${_dir}/${_llvmbox_filename}"
    local _llvmbox_url="https://github.com/rsms/llvmbox/releases/download/v${_llvmbox_version}/${_llvmbox_filename}"
    local _llvmbox_install_dir="${JUVIX_DIR}/llvmbox"

    local _assume_yes="no"
    for arg in "$@"; do
        case "$arg" in
            --help)
                usage
                exit 0
                ;;
            *)
                OPTIND=1
                if [ "${arg%%--*}" = "" ]; then
                    # Long option (other than --help);
                    # don't attempt to interpret it.
                    continue
                fi
                while getopts :hy sub_arg "$arg"; do
                    case "$sub_arg" in
                        h)
                            usage
                            exit 0
                            ;;
                        y)
                            _assume_yes=yes
                            ;;
                        *)
                            ;;
                        esac
                done
                ;;
        esac
    done


    find_shell_name
    local _shell_name="$RETVAL"
    find_profile_path
    local _profile_path="$RETVAL"

    local _install_llvmbox
    if [ "$_assume_yes" = "yes" ] || [ -n "$JUVIX_INSTALLER_ASSUME_YES" ]; then
        _install_llvmbox="yes"
    else
        ask_llvmbox "$_llvmbox_install_dir"
        _install_llvmbox="$RETVAL"
    fi

    local _adjust_profile
    if [ "$_assume_yes" = "yes" ] || [ -n "$JUVIX_INSTALLER_ASSUME_YES" ]; then
        _adjust_profile="yes"
    else
        ask_profile "$_shell_name" "$_profile_path"
        _adjust_profile="$RETVAL"
    fi

    write_env "$_llvmbox_install_dir"

    if [ "$_install_llvmbox" = "yes" ]; then
        ensure mkdir -p "$_dir"
        say 'downloading llvmbox'
        ensure downloader "$_llvmbox_url" "$_llvmbox_file" "$_llvmbox_arch"
        say "installing llvmbox into ${_llvmbox_install_dir}"
        ensure mkdir -p "${_llvmbox_install_dir}"
        ensure tar -xf "$_llvmbox_file" --strip-components=1 -C "${_llvmbox_install_dir}"
    fi

    printf '%s\n' 'info: downloading juvix' 1>&2
    ensure mkdir -p "$_dir"
    ensure downloader "$_juvix_url" "$_juvix_file" "$_juvix_arch"

    printf '%s\n' "info: installing juvix into ${JUVIX_BIN}" 1>&2
    ensure mkdir -p "${JUVIX_BIN}"
    ensure tar -xzf "$_juvix_file" -C "${JUVIX_BIN}"

    adjust_profile "$_adjust_profile" "$_shell_name" "$_profile_path"

    ignore rm "$_juvix_file"
    if [ -f "$_llvmbox_file" ]; then
        ignore rm "$_llvmbox_file"
    fi
    ignore rmdir "$_dir"
}


# Writes scripts to $JUVIX_DIR/env and $JUVIX_DIR/env.fish that, when sourced,
# prepends the ${JUVIX_BIN} directory to $PATH if it is not already present
# there.
write_env() {
    local _llvmbox_install_dir=$1
    ensure mkdir -p "${JUVIX_DIR}"
    local _env_file="${JUVIX_DIR}/env"
    local _fish_env_file="${JUVIX_DIR}/env.fish"
    cat <<-EOF > "$_env_file" || err "Failed to create env file: $_env_file"
case ":\$PATH:" in
    *:"${JUVIX_BIN}":*)
        ;;
    *)
        export PATH="${JUVIX_BIN}:\$PATH"
        ;;
esac
if [ -f "${_llvmbox_install_dir}/bin/clang" ]; then
   export JUVIX_CLANG_PATH="${_llvmbox_install_dir}/bin/clang"
fi
EOF
    cat <<-EOF > "$_fish_env_file" || err "Failed to create env file: $_fish_env_file"
set -gx PATH "$JUVIX_BIN" \$PATH # juvix-env
if [ -f "${_llvmbox_install_dir}/bin/clang" ]; then
   set -gx JUVIX_CLANG_PATH "${_llvmbox_install_dir}/bin/clang"
end
EOF
}

get_ostype() {
    local _osttype
    _ostype="$(uname -s)"

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
    RETVAL="$_ostype"
}

get_cputype() {
    local _cputype
    _cputype="$(uname -m)"

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
    RETVAL="$_cputype"
}

get_juvix_architecture() {
    local _ostype
    get_ostype
    _ostype="$RETVAL"

    local _cputype
    get_cputype
    _cputype="$RETVAL"

    local _arch

    if [ "$_ostype" = linux ] && [ "$_cputype" = aarch64 ]; then
        err "linux-aarch64 is not supported"
    fi

    _arch="${_ostype}-${_cputype}"

    RETVAL="$_arch"
}

get_llvmbox_architecture() {
    local _ostype
    get_ostype
    _ostype="$RETVAL"

    local _cputype
    get_cputype
    _cputype="$RETVAL"

    local _arch

    _arch="${_cputype}"-"${_ostype}"

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
    case ${SHELL:-} in
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
    case ${SHELL:-} in
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

# Ask user if they want to install LLVMbox.
ask_llvmbox() {
    local _llvmbox_install_dir=$1
    local _install_llvmbox
    local _answer

    if [ -z "${JUVIX_INSTALLER_NONINTERACTIVE}" ]; then
        while true; do
                echo "-------------------------------------------------------------------------------"
                echo ""
                echo "Do you want to install the LLVM toolchain in ${_llvmbox_install_dir}?"
                echo ""
                echo "Juvix requires the LLVM toolchain to compile native binaries."
                echo ""
                echo "This installation will not interfere with any other version of LLVM on your system."
                echo ""
                echo "[Y] Yes  [N] No  [?] Help (default is \"Y\")."
                echo ""
                read -r _answer </dev/tty
            case $_answer in
                [Yy]* | "")
                    _install_llvmbox="yes"
                    break
                    ;;
                [Nn]*)
                    _install_llvmbox="no"
                    break
                    ;;

                *)
                    ;;
            esac
        done
    else
        _install_llvmbox="no"
    fi
    RETVAL="$_install_llvmbox"
}

# Ask user if they want to adjust the shell profile.
ask_profile() {
    local _shell_name=$1
    local _profile_path=$2
    if [ -z "$_shell_name" ] ; then
        say "No shell detected"
        RETVAL="no"
        return
    fi

    local _answer
    local _adjust_profile

    if [ -z "${JUVIX_INSTALLER_NONINTERACTIVE}" ]; then
        while true; do
                echo "-------------------------------------------------------------------------------"
                echo ""
                echo "Detected $_shell_name shell on your system..."
                echo "Do you want to automatically setup the shell environment by modifying \"${_profile_file}\"?"
                echo ""
                echo "[Y] Yes  [N] No  [?] Help (default is \"Y\")."
                echo ""
                read -r _answer </dev/tty
            case $_answer in
                [Yy]* | "")
                    _adjust_profile="yes"
                    break
                    ;;
                [Nn]*)
                    _adjust_profile="no"
                    break
                    ;;

                *)
                    ;;
            esac
        done
    else
        _adjust_profile="no"
    fi
    RETVAL="$_adjust_profile"
}

# Adjust the user profile to prepend the JUVIX_BIN to the PATH
adjust_profile() {
    local _adjust_profile=$1
    local _shell_name=$2
    local _profile_path=$3

    local _env_file=
    case "$_adjust_profile" in
        yes)
            case "$_shell_name" in
                "")
                    warn_path "Couldn't figure out login shell!"
                    return
                    ;;
                fish)
                    _env_file="env.fish"
                    sed -i -e '/# juvix-env$/ s/^#*/#/' "${_profile_path}"
                    printf "\n%s" "[ -f \"${JUVIX_DIR}/env.fish\" ] && source \"${JUVIX_DIR}/env.fish\" # juvix-env" >> "${_profile_path}"
                    ;;
                bash)
                    _env_file="env"
                    sed -i -e '/# juvix-env$/ s/^#*/#/' "${_profile_path}"
                    printf "\n%s" "[ -f \"${JUVIX_DIR}/env\" ] && source \"${JUVIX_DIR}/env\" # juvix-env" >> "${_profile_path}"
                    ;;

                zsh)
                    _env_file="env"
                    sed -i -e '/# juvix-env$/ s/^#*/#/' "${_profile_path}"
                    printf "\n%s" "[ -f \"${JUVIX_DIR}/env\" ] && source \"${JUVIX_DIR}/env\" # juvix-env" >> "${_profile_path}"
                    ;;
            esac
            echo
            echo "==============================================================================="
            echo
            echo "OK! ${_profile_path} has been modified. Restart your terminal for the changes to take effect,"
            echo "or type \"source ${JUVIX_DIR}/${_env_file}\" to apply them in your current terminal session."
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
