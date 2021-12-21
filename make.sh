#!/usr/bin/env bash

set -eo pipefail

source utils/message.sh
source utils/parseopts.sh

_script_dir="$(realpath "$(dirname "$0")")"
_build_dir="$_script_dir/build"
_comnetsemu_dir="$_script_dir/comnetsemu"
_utils_dir="$_script_dir/utils"
_virtualenv_dir="$_script_dir/env"

_force=0

declare -A _targets=(
    [clean]="clean"
    [comnetsemu-box]="comnetsemu_box"
    [docker]="srsran_docker"
    [vagrant]="project_vagrant"
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
    -h    display this help message and exit.
EOF
}

# Package comnetsemu as a Vagrant base box
comnetsemu_box() {
    if [ -f "$_build_dir"/comnetsemu.box ] && (( ! _force )); then
        warning "Nothing to do"
        return
    fi

    _create_build_dir
    _git_submodule

    msg "Packaging comnetsemu with Vagrant"

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
    _comnetsemu_version=$(git -C comnetsemu describe --tags)
    vagrant box add -c -f --name comnetsemu-"${_comnetsemu_version/v/}" "$_build_dir"/comnetsemu.box
}

# Builds srsRAN in a Docker container and saves it as tarred image
# to avoid having to build it inside the VM
srsran_docker() {
    if [ -f "$_build_dir"/srsran.tar ] && (( ! _force )); then
        warning "Nothing to do"
        return
    fi

    _create_build_dir

    docker build -t srsran "$_script_dir"
	docker save -o "$_build_dir"/srsran.tar srsran
}

# Create a new Vagrant VM with comnetsemu as base image, the upload all project files
# See Vagrantfile 
project_vagrant() {
    _status=$(vagrant global-status | grep comnetsemu-srsran)
    if [ "$_status" ] && [[ "$(echo "$_status" | awk '{print $4}')" = "running" ]] && (( ! _force )); then
        warning "Nothing to do"
        return
    fi

    comnetsemu_box
    # srsran_docker

    # TODO: integrate docker in comnetsemu, write topology and tests
    msg "Starting comnetsemu-srsran"
    vagrant up
}

virtualenv() {
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

clean() {
    rm_msg() {
        msg2 "Removing ${*: -1}"
        rm "$@"
    }

    # Deactivate virtualenv if running
    deactivate || true
    rm_msg -rf "$_build_dir"
    rm_msg -rf "$_virtualenv_dir"
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
        exit 1
    fi
    set -- "${OPTRET[@]}"
    unset OPT_SHORT OPT_LONG OPTRET

    while true; do
        case "$1" in
            -f|--force) _force=1 ;;
            -h|--help)  _usage; exit 0 ;;
            --)         shift; break 2 ;;
        esac
        shift
    done

    # Exit if target does not exist
    if [[ ! -v _targets["$1"] ]]; then
        error "Uknown target: $1"
        _usage
        exit 1
    fi

    msg "Running target $1"
    ${_targets["$1"]}
    exit 0
}