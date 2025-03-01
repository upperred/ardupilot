#!/usr/bin/env bash
set -e
set -x

CWD=$(pwd)
OPT="/opt"

ASSUME_YES=false
QUIET=false
sep="##############################################"

OPTIND=1  # Reset in case getopts has been used previously in the shell.
while getopts "yq" opt; do
    case "$opt" in
        \?)
            exit 1
            ;;
        y)  ASSUME_YES=true
            ;;
        q)  QUIET=true
            ;;
    esac
done

BASE_PKGS="base-devel ccache git gsfonts tk wget gcc"
SITL_PKGS="python-pip python-setuptools python-wheel python-wxpython opencv python-numpy python-scipy"
PX4_PKGS="lib32-glibc zip zlib ncurses"

PYTHON_PKGS="future lxml pymavlink MAVProxy pexpect argparse matplotlib pyparsing geocoder pyserial empy==3.3.4 dronecan packaging setuptools wheel"

# GNU Tools for ARM Embedded Processors
# (see https://launchpad.net/gcc-arm-embedded/)
ARM_ROOT="gcc-arm-none-eabi-10-2020-q4-major"
ARM_TARBALL="$ARM_ROOT-x86_64-linux.tar.bz2"
ARM_TARBALL_URL="https://firmware.ardupilot.org/Tools/STM32-tools/$ARM_TARBALL"
ARM_TARBALL_CHECKSUM="21134caa478bbf5352e239fbc6e2da3038f8d2207e089efc96c3b55f1edcd618" 

# Ardupilot Tools
ARDUPILOT_TOOLS="ardupilot/Tools/autotest"

function maybe_prompt_user() {
    if $ASSUME_YES; then
        return 0
    else
        read -p "$1"
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            return 0
        else
            return 1
        fi
    fi
}

sudo usermod -a -G uucp "$USER"

sudo pacman -Syu --noconfirm --needed $BASE_PKGS $SITL_PKGS $PX4_PKGS

python3 -m venv --system-site-packages "$HOME"/venv-ardupilot

# activate it:
SOURCE_LINE="source $HOME/venv-ardupilot/bin/activate"
$SOURCE_LINE

if [[ -z "${DO_PYTHON_VENV_ENV}" ]] && maybe_prompt_user "Make ArduPilot venv default for python [N/y]?" ; then
    DO_PYTHON_VENV_ENV=1
fi

if [[ $DO_PYTHON_VENV_ENV -eq 1 ]]; then
    echo "$SOURCE_LINE" >> ~/.bashrc
else
    echo "Please use \`$SOURCE_LINE\` to activate the ArduPilot venv"
fi

python3 -m pip -q install -U $PYTHON_PKGS

(
    cd /usr/lib/ccache
    if [ ! -f arm-none-eabi-g++ ]; then
       sudo ln -s /usr/bin/ccache arm-none-eabi-g++
    fi
    if [ ! -f arm-none-eabi-g++ ]; then
        sudo ln -s /usr/bin/ccache arm-none-eabi-gcc
    fi
)

if [ ! -d $OPT/$ARM_ROOT ]; then
    (
        cd $OPT;

        # Check if file exists and verify checksum
        download_required=false
        if [ -e "$ARM_TARBALL" ]; then
            echo "File exists. Verifying checksum..."

            # Calculate the checksum of the existing file
            ACTUAL_CHECKSUM=$(sha256sum "$ARM_TARBALL" | awk '{ print $1 }')

            # Compare the actual checksum with the expected one
            if [ "$ACTUAL_CHECKSUM" == "$ARM_TARBALL_CHECKSUM" ]; then
                echo "Checksum valid. No need to redownload."
            else
                echo "Checksum invalid. Redownloading the file..."
                download_required=true
                sudo rm $ARM_TARBALL
            fi
        else
            echo "File does not exist. Downloading..."
            download_required=true
        fi

        if $download_required; then
            sudo wget -O "$ARM_TARBALL" --progress=dot:giga $ARM_TARBALL_URL
        fi

        sudo tar xjf ${ARM_TARBALL}
    )
fi

exportline="export PATH=$OPT/$ARM_ROOT/bin:\$PATH";
if ! grep -Fxq "$exportline" ~/.bashrc ; then
    if maybe_prompt_user "Add $OPT/$ARM_ROOT/bin to your PATH [N/y]?" ; then
        echo "$exportline" >> ~/.bashrc
        . "$HOME/.bashrc"
    else
        echo "Skipping adding $OPT/$ARM_ROOT/bin to PATH."
    fi
fi

exportline2="export PATH=$CWD/$ARDUPILOT_TOOLS:\$PATH";
if  ! grep -Fxq "$exportline2" ~/.bashrc ; then
    if maybe_prompt_user "Add $CWD/$ARDUPILOT_TOOLS to your PATH [N/y]?" ; then
        echo "$exportline2" >> ~/.bashrc
        . "$HOME/.bashrc"
    else
        echo "Skipping adding $CWD/$ARDUPILOT_TOOLS to PATH."
    fi
fi

SCRIPT_DIR=$(dirname $(realpath ${BASH_SOURCE[0]}))
(
    cd "$SCRIPT_DIR"
    git submodule update --init --recursive
)

echo "Done. Please log out and log in again."
