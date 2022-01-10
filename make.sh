#!/usr/bin/env bash
#
#   make.sh - overly complicated bash build system
#
# Functions starting with "make::" are Makefile-like targets. Each function is
# to check its own requirements for running and return silently if they are met.
# Documentation is automatically scraped from the file as follows: when 
# "--help <target>" is called, a comment in the form "#:(<target>)" is grepped
# from this file (with the regex /^#:\(($1)\)\s+(.*)$/) and shown as text 
# (see _target_help function below). The comment can be multiple lines with the prefix.
# Script usage is shown on "./make.sh --help", and target-specific help with
# "./make.sh --help <target>".
# This script is also shellcheck-tested, for what it's worth.

source utils/message.sh
source utils/parseopts.sh

_script="$(realpath "$0")"
_script_dir="$(realpath "$(dirname "$0")")"
_build_dir="$_script_dir/build"
_comnetsemu_dir="$_script_dir/comnetsemu"
_docker_dir="$_script_dir/docker"
_utils_dir="$_script_dir/utils"
_virtualenv_dir="$_script_dir/env"

_force=0
_help=0

# Print usage
_usage() {
    local _targets
    _targets=$(declare -F | awk '{print $NF}' | sed -nE "s/(make::)(.*)$/\2/p" | sort | tr '\n' ' ')
    cat <<EOF
./$(basename "$0") - Build script for comnetsemu-srsRAN

Usage: $0 [options] <target>
  Targets: $_targets

  Options:
    -f, --force    
        force the target to run even if files have already been built.

    -ff, --force --force
        force ALL the targets in the chain to run even if not necessary.
        Example: 
            make::vagrant will run make::docker and make::comnetsemu_box with -ff active

    -h, --help    
        display this help message or target-specific help (--help <target>).
EOF
}

# Shows help/documentation for a specific target
# Documentation syntax (ignore first #):
# #:(<target name>) <documentation>
# #:(<target name>) <other line of documentation>
_target_help() {
    local _help
    # Get line with a specific comment and use it as documentation
    # Look for lines starting with `#:(<target>)`
    _help=$(sed -nE "s/^#:\(($1)\)\s+(.*)$/\2/p" "$_script")
    msg "./make.sh $1"
    # Print all lines with plain()
    IFS=$'\n'; for _line in $_help; do
        plain "$_line"
    done
}

#:(build_dir) Creates $_build_dir if not present
make::build_dir() {
    mkdir -p "$_build_dir"
}

#:(git_submodules) Download or update Git submodules
make::git_submodules() {
    if [ -n "$(find "$_comnetsemu_dir" -maxdepth 0 -type d -empty 2>/dev/null)" ]; then
        msg "Downloading comnetsemu as submodule"
        git submodule update --init
    else
        git submodule update --recursive --remote --init
    fi
}

#:(docker) Builds srsRAN in a Docker container and saves it as tarred image to avoid having to build it inside the VM
make::docker() {
    if [ -f "$_build_dir"/srsran.tar ] && (( ! _force )); then
        return
    fi

    make::build_dir

    msg "Building srsRAN in Docker container"
    docker build -t srsran "$_docker_dir"
	docker save -o "$_build_dir"/srsran.tar srsran
}

#:(slides_live) Starts reveal-md in a Docker container with live reload
make::slides_live() {
    if docker inspect --type=container marp &>/dev/null && (( ! _force )); then
        return
    fi

    docker stop marp &>/dev/null || true
    docker run --rm -d --init \
        -v "$(pwd)"/slides:/home/marp/app \
        -e LANG="$LANG" -e MARP_USER="$(id -u):$(id -g)" \
        -p 8080:8080 -p 37717:37717 \
        --name marp \
        marpteam/marp-cli --html -s .
    
    sleep 1s
    if docker inspect --type=container marp &>/dev/null; then
        xdg-open http://localhost:8080
    fi
}

#:(vagrant) Create a new Vagrant VM with comnetsemu as base image, the upload all project files (see Vagrantfile)
make::vagrant() {
    local _in_vagrant
    _in_vagrant() {
        vagrant ssh -c "$1" || die "${2:-Error running command in VM}"
    }

    local _status
    _status=$(vagrant global-status | grep comnetsemu-srsran | awk '{print $2,$4}')
    if [[ "$_status" ]] && [[ "$(echo "$_status" | awk '{print $NF}')" = "running" ]]; then
        if (( ! _force )); then
            return
        fi
        warning "VM already running! Restarting"
        vagrant reload
    fi

    # Only run these if -ff was used (see --help)
    _force=$(( _force > 0 ? _force-1 : 0 ))
    make::docker

    msg "Starting comnetsemu-srsran"
    vagrant up || die "Vagrant error or forced exit"

    msg "Importing srsran docker image"
    _in_vagrant "docker load -i /home/vagrant/project/$(basename "$_build_dir")/srsran.tar" "Error loading srsRAN image in VM"

    # TODO: write topology and tests
    # msg "Starting scripts in VM"
}

#:(virtualenv) Setup virtualenv with comnetsemu's dependencies for editor completion etc.
#:(virtualenv) WARNING: running comnetsemu code in the virtualenv is not supported so be careful
make::virtualenv() {
    if [ -f "$_virtualenv_dir"/bin/activate ] && (( ! _force )); then
        warning "Nothing to do"
        return
    fi

    msg "Creating virtualenv"
    rm -rf "$_virtualenv_dir"
    python -m venv "$_virtualenv_dir"
    # shellcheck disable=SC1091
    source "$_virtualenv_dir"/bin/activate
    msg "Installing dependencies"
    pip install wheel
    pip install docker pyroute2 requests
    pip install git+https://github.com/mininet/mininet.git@2.3.0
    pip install git+https://github.com/faucetsdn/ryu.git@v4.34
    pushd "$_comnetsemu_dir" >/dev/null || die "Error pushd directory $_comnetsemu_dir"
    python setup.py install
    popd >/dev/null || die "Error popd directory $_comnetsemu_dir"
    deactivate || true
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
    rm_msg -rf ./*VBoxHeadless*.log
}

#:(clean_deep) DANGEROUS! Like clean(), plus remove comnetsemu box and destroy VM
make::clean_deep() {
    local _rm_msg
    _rm_msg() {
        msg2 "Removing ${*: -1}"
        rm "$@"
    }

    # TODO: ask confirmation?
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

    if ! command -v vboxmanage &>/dev/null; then
        error "Virtualbox not installed!"
    else
        msg2 "Virtualbox OK"
    fi

    if ! command -v vagrant &>/dev/null; then
        error "Vagrant not installed!"
    else
        msg2 "Vagrant OK"
        _vagrant_check "comnetsemu-srsran"
    fi

    local _venvs
    _venvs=$(find "$(realpath --relative-base "$_script_dir" "$_script_dir")" -type f -name "activate")
    if [[ -n "$_venvs" ]]; then
        msg2 "Found python virtualenv at:"
        dirname "$(dirname "$_venvs")" | sed -nE 's/^.*/\t&/p'
    else
        msg2 "No python virtualenv found"
    fi

    msg2 "Build directory ($_build_dir) contains:"
    # Do some tree | sed trickery to indent lines and get a nice relative directory
    tree -achsCDF --noreport "$(realpath --relative-base "$_script_dir" "$_build_dir")" | sed -nE 's/^.*/\t&/p'
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
            -f|--force) (( _force++ )) ;;
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
        error "Target not specified! Use --help for more information."
        _usage
        exit 1
    fi

    # "help" is not a target but we know what the user meant
    if [[ "$1" = "help" ]]; then
        error "Target 'help' does not exist (use --help)! Showing help anyways"
        _usage
        exit 1
    fi

    # Exit if target does not exist (checks if function is defined in this script)
    if ! declare -F -- make::"$1" >/dev/null; then
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
    if [[ $_force -gt 1 ]]; then
        msg "Running target $1 at full force"
    else
        msg "Running target $1"
    fi
    make::"$1"
    exit 0
}