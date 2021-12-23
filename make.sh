#!/usr/bin/env bash
#
#   make.sh - overly complicated bash build system
# 
# Functions starting with "make::" are Makefile-like targets. Each function is
# to check its own requirements for running and return silently if they are met.
# Documentation is automatically scraped from the file as follows: when 
# "--help <target>" is called, a comment in the form "#:(<target>)" is grepped
# from this file (with the regex /^#:\(($1)\)\s+(.*)$/) and shown as text 
# (see _target_help function below).
# Script usage is shown on "./make.sh --help", and target-specific help with
# "./make.sh --help <target>".
# This script is also shellcheck-tested, for what it's worth.

source utils/message.sh
source utils/parseopts.sh

_script="$(realpath "$0")"
_script_dir="$(realpath "$(dirname "$0")")"
_build_dir="$_script_dir/build"
_comnetsemu_dir="$_script_dir/comnetsemu"
_utils_dir="$_script_dir/utils"
_virtualenv_dir="$_script_dir/env"

_force=0
_help=0

declare -A _targets=(
    [check]="check"
    [clean]="clean"
    [clean-deep]="clean_deep"
    [comnetsemu-box]="comnetsemu_box"
    [docker]="docker"
    [vagrant]="vagrant"
    [virtualenv]="virtualenv"
)

# Creates $_build_dir if not present
_create_build_dir() {
    mkdir -p "$_build_dir"
}

# Download submodules
_git_submodule() {
    if [ -n "$(find "$_comnetsemu_dir" -maxdepth 0 -type d -empty 2>/dev/null)" ]; then
        msg "Downloading comnetsemu as submodule"
        git submodule update --init
    fi
}

# Print usage
_usage() {
    cat <<EOF
$(basename "$0") - Build script for comnetsemu-srsRAN

Usage: $0 [options] <target>
  Targets: ${!_targets[*]}

  Options:
    -f    force the target to run even if files have already been built.
    -h    display this help message or target-specific help (--help <target>).
EOF
}

# Shows help/documentation for a specific target
# Documentation syntax (ignore first #):
# #:(<target name>) <documentation>
_target_help() {
    local _help
    # Get line with a specific comment and use it as documentation
    # Look for lines starting with `#:(<target>)`
    _help=$(sed -nE "s/^#:\(($1)\)\s+(.*)$/\2/p" "$_script")
    msg "./make.sh $1"
    plain "$_help"
}

#:(comnetsemu-box) Package comnetsemu as a Vagrant base box
make::comnetsemu_box() {
    if [ -f "$_build_dir"/comnetsemu.box ] && (( ! _force )); then
        return
    fi

    _create_build_dir
    _git_submodule

    msg "Packaging comnetsemu with Vagrant"

    local _status
    _status=$(vagrant global-status | grep comnetsemu)
    if [ ! "$_status" ] || [[ "$(echo "$_status" | awk '{print $4}')" = "poweroff" ]]; then
        msg2 "Starting comnetsemu"
        pushd "$_comnetsemu_dir" >/dev/null || die "Error pushd directory $_comnetsemu_dir"
        vagrant up
        popd >/dev/null || die "Error popd directory $_comnetsemu_dir"
    fi
    
    msg2 "Compressing box. This may take several minutes"
    pushd "$_comnetsemu_dir" >/dev/null || die "Error pushd directory $_comnetsemu_dir"
    vagrant package comnetsemu
    mv package.box "$_build_dir"/comnetsemu.box
    popd >/dev/null || die "Error popd directory $_comnetsemu_dir"

    msg "Adding comnetsemu box to Vagrant"
    local _comnetsemu_version
    _comnetsemu_version=$(git -C comnetsemu describe --tags)
    vagrant box add -c -f --name comnetsemu-"${_comnetsemu_version/v/}" "$_build_dir"/comnetsemu.box
}

#:(docker) Builds srsRAN in a Docker container and saves it as tarred image to avoid having to build it inside the VM
make::docker() {
    if [ -f "$_build_dir"/srsran.tar ] && (( ! _force )); then
        return
    fi

    _create_build_dir

    msg "Building srsRAN in Docker container"
    docker build -t srsran "$_script_dir"
	docker save -o "$_build_dir"/srsran.tar srsran
}

#:(vagrant) Create a new Vagrant VM with comnetsemu as base image, the upload all project files (see Vagrantfile) 
make::vagrant() {
    local _status
    _status=$(vagrant global-status | grep comnetsemu-srsran)
    if [[ "$_status" ]] && [[ "$(echo "$_status" | awk '{print $4}')" = "running" ]]; then
        if (( _force )); then
            warning "VM already running! Restarting"
            vagrant reload
        fi
        return
    fi

    make::comnetsemu_box
    # make::docker

    # TODO: integrate docker in comnetsemu, write topology and tests
    msg "Starting comnetsemu-srsran"
    vagrant up
}

#:(virtualenv) Setup virtualenv with comnetsemu's dependencies for editor completion etc
make::virtualenv() {
    if [ -f "$_virtualenv_dir"/bin/activate ]; then
        warning "Nothing to do"
        return
    fi

    msg "Creating virtualenv"
    python -m venv "$_virtualenv_dir"
    # shellcheck disable=SC1091
    source "$_virtualenv_dir"/bin/activate
    msg "Installing dependencies"
    pip install docker pyroute2 requests mininet ryu
    deactivate
}

#:(clean) Remove files created by this project
make::clean() {
    local _rm_msg
    _rm_msg() {
        msg2 "Removing ${*: -1}"
        rm "$@"
    }

    # Deactivate virtualenv if running
    deactivate || true
    rm_msg -rf "$_virtualenv_dir"
}

#:(clean-deep) DANGEROUS! Like clean(), plus remove comnetsemu box and destroy VM
make::clean_deep() {
    local _rm_msg
    _rm_msg() {
        msg2 "Removing ${*: -1}"
        rm "$@"
    }

    # TODO: ask confirmation

    clean
    rm_msg -rf "$_build_dir"
    vagrant destroy -f -g
}

#:(check) Runs various system checks (running VMs, build/ and other directories)
make::check() {
    local _vagrant_check
    _vagrant_check() {
        local _status
        _status=$(vagrant global-status | grep -E "$1\s")
        if [[ "$_status" ]]; then
            msg2 "$1 (Vagrant): $(echo "$_status" | awk '{print $4}')"
        else
            msg2 "$1 (Vagrant): not created"
        fi
    }

    msg "Running checks"

    _vagrant_check "comnetsemu-srsran"
    _vagrant_check "comnetsemu"

    msg2 "Build directory ($_build_dir) contains:"
    # Do some tree | sed trickery to indent lines and get a nice relative directory
    tree -achsCDF --noreport "$(realpath --relative-base "$_script_dir" "$_build_dir")" | sed -nE 's/^.*/\t&/p'

    local _venvs
    _venvs=$(find "$(realpath --relative-base "$_script_dir" "$_script_dir")" -type f -name "activate")
    if [[ -n "$_venvs" ]]; then
        msg2 "Found python virtualenv at:"
        dirname "$(dirname "$_venvs")" | sed -nE 's/^.*/\t&/p'
    else
        msg2 "No python virtualenv found"
    fi
}

{
    # Colors
    colorize

    # Root is bad
    if [[ "$EUID" = 0 ]]; then
        die "Don't run this script as root!"
    fi

    # Parse command line options
    OPT_SHORT="fh"
    OPT_LONG=("force" "help")
    if ! parseopts "$OPT_SHORT" "${OPT_LONG[@]}" -- "$@"; then
        die "Error parsing command line"
    fi
    set -- "${OPTRET[@]}"
    unset OPT_SHORT OPT_LONG OPTRET

    while true; do
        case "$1" in
            -f|--force) _force=1 ;;
            -h|--help)  _help=1 ;;
            --)         shift; break 2 ;;
        esac
        shift
    done

    # No targets were passed from command line
    if [[ "$#" = 0 ]]; then
        # Allow calling just --help
        if (( _help )); then
            _usage
            exit 0
        fi

        # Otherwise, error
        error "Target not specified!"
        _usage
        exit 1
    fi

    # "help" is not a target but we know what the user meant
    if [[ "$1" = "help" ]]; then
        error "Target 'help' does not exist (use --help)! Showing help anyways"
        _usage
        exit 1
    fi

    # Exit if target does not exist
    if [[ ! -v _targets["$1"] ]]; then
        error "Uknown target: $1"
        _usage
        exit 1
    fi

    # Show help for target if --help <target> was used
    if (( _help )); then
        _target_help "$1"
        exit 0
    fi

    # Run the actual target
    msg "Running target $1"
    make::"${_targets["$1"]}"
    exit 0
}