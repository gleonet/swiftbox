#!/bin/bash

if [ "E`lsb_release -i --short`" = "EUbuntu" ]
then
    UBUNTU_VERSION=`lsb_release -r --short`
    if [ ${UBUNTU_VERSION//./} -gt 1804 ] && [ ${UBUNTU_VERSION//./} -lt 2004 ]
    then
      UBUNTU_VERSION="18.04"
    fi
else
    echo "This program only support Ubuntu. "
    exit 255
fi

SWIFTBOX_VERSION="0.4.4"
INSTALL_DIR="/usr/bin"

full-reinit() {
    sed -i "/$WORKING_DIR\/env.sh/d;/$ANOTHER_DIR\/env.sh/d" $1
    echo "source /opt/swiftbox/env.sh" >> $1
    echo "source $HOME/.swiftbox/env.sh" >> $1
}

enable-swiftbox() {
    if [ -e $ANOTHER_DIR/env.sh ]
    then
        if [ -e $HOME/.zshrc ]
        then
            full-reinit $HOME/.zshrc
        fi
        if [ -e $HOME/.bashrc ]
        then
            full-reinit $HOME/.bashrc
        elif [ -e $HOME/.bash_profile ]
        then
            full-reinit $HOME/.bash_profile
        fi
    else
        if [ -e $HOME/.zshrc ]
        then
            echo "source $WORKING_DIR/env.sh" >> $HOME/.zshrc
        fi
        if [ -e $HOME/.bashrc ]
        then
            echo "source $WORKING_DIR/env.sh" >> $HOME/.bashrc
        elif [ -e $HOME/.bash_profile ]
        then
            echo "source $WORKING_DIR/env.sh" >> $HOME/.bash_profile
        fi
    fi
}

init-env() {
    mkdir $WORKING_DIR
    mkdir $WORKING_DIR/temp
    mkdir $WORKING_DIR/toolchain
    mkdir $WORKING_DIR/download
    echo "Created swiftbox working directory at $WORKING_DIR. "
    echo -e "if [ -e $WORKING_DIR/.swift-version ]\nthen\n\texport PATH=$WORKING_DIR/toolchain/swift-\`cat $WORKING_DIR/.swift-version\`/usr/bin:\$PATH\nfi" > $WORKING_DIR/env.sh
    if [ `id -u` -eq 0 ]
    then
        ln -s $WORKING_DIR/env.sh /etc/profile.d/swiftbox.sh
    fi
    enable-swiftbox
    $SUDO_FLAG apt-get update
    $SUDO_FLAG apt-get install clang libicu-dev wget -y
    wget -q -O - https://swift.org/keys/all-keys.asc | $SUDO_FLAG gpg --import -
    echo "swiftbox has been successfully set up. "
}

format-version() {
    if [ "E$1" = E ]
    then
        echo "Please specify Swift version. "
        return 12
    fi
    local VERSION_ARRAY=(${1//./ })
    for var in ${VERSION_ARRAY[@]}
    do
        if [ `echo $var | sed 's/[0-9]//g'` ]
        then
            echo "Invalid Swift version, try x.x.x or x.x"
            return 1
        fi
    done
    case ${#VERSION_ARRAY[@]} in
    2)
        echo "$((10#${VERSION_ARRAY[0]})).$((10#${VERSION_ARRAY[1]}))"
    ;;
    3)
        if [ ${VERSION_ARRAY[2]} -eq 0 ]
        then
            echo "$((10#${VERSION_ARRAY[0]})).$((10#${VERSION_ARRAY[1]}))"
        else
            echo "$((10#${VERSION_ARRAY[0]})).$((10#${VERSION_ARRAY[1]})).$((10#${VERSION_ARRAY[2]}))"
        fi
    ;;
    *)
        echo "Invalid Swift version, try x.x.x or x.x"
        return 1
    ;;
    esac
}

remove-swift() {
    if [ ! -d $WORKING_DIR/toolchain/swift-$1 ]
    then
        echo "Swift $1 has not been kept, you can get it with: $0 get $1"
        return 4
    else
        rm -rf $WORKING_DIR/toolchain/swift-$1
        if [ E`default-version` = E$1 ]
        then
            disable-swift
        fi
        echo "Successfully removed Swift $1. "
    fi
}

disable-swift() {
    local SWIFT_VERSION=`default-version`
    rm -f $WORKING_DIR/.swift-version
    ensure-env
    if [ ! E$SWIFT_VERSION = E ]
    then
        echo "Swift $SWIFT_VERSION is now disabled. "
    fi
}

default-version() {
    if [ ! -e $WORKING_DIR/.swift-version ]
    then 
        echo ""
    else
        cat $WORKING_DIR/.swift-version
    fi
}

check-version() {
    local DOWNLOAD_URL="https://swift.org/builds/swift-$1-release/ubuntu${UBUNTU_VERSION//./}/swift-$1-RELEASE/swift-$1-RELEASE-ubuntu$UBUNTU_VERSION.tar.gz"
    wget --no-check-certificate -q --spider $DOWNLOAD_URL
    WGET_RESULT=$?
    if [ $WGET_RESULT -eq 8 ]
    then
        echo "Swift $1 does not exist or does not support your Ubuntu version. "
        return 2
    elif [ $WGET_RESULT -ge 4 ]
    then
        echo "Network error. Please check your Internet connection and proxy settings. "
        return 5
    elif [ $WGET_RESULT -ge 1 ]
    then
        echo "Please check your wget config. "
        return 255
    fi
}

get-swift() {
    cd $WORKING_DIR
    local NEW_VERSION=$1
    local FILE_NAME="swift-$NEW_VERSION-RELEASE-ubuntu$UBUNTU_VERSION"
    local DOWNLOAD_URL="https://swift.org/builds/swift-$NEW_VERSION-release/ubuntu${UBUNTU_VERSION//./}/swift-$NEW_VERSION-RELEASE/$FILE_NAME.tar.gz"
    check-version $NEW_VERSION
    VERSION_AVAILABILITY=$?
    if [ ! $VERSION_AVAILABILITY -eq 0 ]
    then
        return $VERSION_AVAILABILITY
    fi
    if [ -e "download/$FILE_NAME.tar.gz.sig" ]
    then
        wget -c -t 5 -P download "$DOWNLOAD_URL.sig"
    else
        if [ -e "download/$FILE_NAME.tar.gz" ]
        then
            wget -c -t 0 -P download $DOWNLOAD_URL
        else
            wget -t 5 -P download $DOWNLOAD_URL
        fi
        wget -t 5 -P download "$DOWNLOAD_URL.sig"
    fi
    $SUDO_FLAG gpg --keyserver hkp://pool.sks-keyservers.net --refresh-keys Swift
    $SUDO_FLAG gpg --verify "download/$FILE_NAME.tar.gz.sig"
    tar -xzf "download/$FILE_NAME.tar.gz" -C "temp"
    mv "temp/$FILE_NAME" "toolchain/swift-$NEW_VERSION"
    if [ ! -e .swift-version ]
    then
        echo "Automatically set Swift $NEW_VERSION as default. "
        use-version $NEW_VERSION
    fi
}

use-version() {
    is-kept $1
    if [ $? -eq 0 ]
    then
        echo $1 > $WORKING_DIR/.swift-version
        ensure-env
        source $WORKING_DIR/env.sh
        hash -r
        echo "Now using Swift $1. "
    else
        echo "Error: Swift $1 has not been installed yet. "
        return 20
    fi
}

is-kept() {
    if [ -d $WORKING_DIR/toolchain/swift-$1 ]
    then
        return 0
    else
        return 1
    fi
}

ensure-env() {
    if [ ! -e $WORKING_DIR ]
    then
        echo "It seems you're using swiftbox for the very first time. Let's set up the supporting environment. "
        init-env
    else
        if [ ! E`default-version` = E ]
        then
            hash swift 2>/dev/null || enable-swiftbox
        fi
        hash -r
        rm -rf $WORKING_DIR/temp/*
    fi
}

if [ `id -u` -eq 0 ]
then
    WORKING_DIR="/opt/swiftbox"
    ANOTHER_DIR="$HOME/.swiftbox"
else
    WORKING_DIR="$HOME/.swiftbox"
    ANOTHER_DIR="/opt/swiftbox"
    SUDO_FLAG="sudo"
fi

if [ $# -eq 0 ]
then
    echo "Please specify a command. "
    exit 240
fi

case $1 in
get)
    ensure-env
    FORMAT_VERSION=`format-version $2`
    FORMAT_RESULT=$?
    if [ ! $FORMAT_RESULT -eq 0 ]
    then
        echo $FORMAT_VERSION
        exit $FORMAT_RESULT
    fi
    if [ E$FORMAT_VERSION = E`default-version` ]
    then
        echo "Swift $FORMAT_VERSION is kept locally and set to default. "
        exit 34
    fi
    is-kept $FORMAT_VERSION
    if [ $? -eq 0 ]
    then
        echo "Swift $FORMAT_VERSION is kept locally, you can enable it with: $0 use $FORMAT_VERSION"
        exit 33
    else
        get-swift $FORMAT_VERSION
    fi
;;
remove)
    ensure-env
    FORMAT_VERSION=`format-version $2`
    FORMAT_RESULT=$?
    if [ ! $FORMAT_RESULT -eq 0 ]
    then
        echo $FORMAT_VERSION
        exit $FORMAT_RESULT
    else
        remove-swift $FORMAT_VERSION
        exit $?
    fi
;;
use)
    FORMAT_VERSION=`format-version $2`
    FORMAT_RESULT=$?
    if [ ! $FORMAT_RESULT -eq 0 ]
    then
        echo $FORMAT_VERSION
        exit $FORMAT_RESULT
    else
        use-version $FORMAT_VERSION
        exit $?
    fi
;;
disable)
    disable-swift
    exit $?
;;
clean)
    ensure-env
    rm -rf $WORKING_DIR/temp/*
    rm -rf $WORKING_DIR/download/*
;;
version)
    echo $SWIFTBOX_VERSION
;;
lookup)
    FORMAT_VERSION=`format-version $2`
    FORMAT_RESULT=$?
    if [ ! $FORMAT_RESULT -eq 0 ]
    then
        echo $FORMAT_VERSION
        exit $FORMAT_RESULT
    fi
    check-version $FORMAT_VERSION
    VERSION_AVAILABILITY=$?
    if [ ! $VERSION_AVAILABILITY -eq 0 ]
    then
        exit $VERSION_AVAILABILITY
    fi
    echo "Swift $FORMAT_VERSION is available for Ubuntu $UBUNTU_VERSION. "
;;
update)
    if [ ! $(cd `dirname $0`; pwd) = $INSTALL_DIR ]
    then
        echo "swiftbox is not installed to system, update unavailable. "
        echo "You can install it with: $0 install"
        exit 254
    fi
    INSTALL_SCRIPT=`wget -q -O- https://raw.githack.com/stevapple/swiftbox/master/install.sh`
    WGET_RESULT=$?
    if [ $WGET_RESULT -ge 4 ]
    then
        echo "Error: Please check your Internet connection and proxy settings. "
        exit $WGET_RESULT
    elif [ $WGET_RESULT -ge 1 ]
    then
        echo "Error: Please check your wget config. "
        exit $WGET_RESULT
    fi
    echo $INSTALL_SCRIPT | sh
    exit $?
;;
install)
    if [ ! $(cd `dirname $0`; pwd) = $INSTALL_DIR ]
    then
        echo "swiftbox is already installed to system. "
        exit 1
    fi
    $SUDO_FLAG cp $0 $INSTALL_DIR/swiftbox
    echo "Successfully installed swiftbox to system. "
;;
list)
    ensure-env
    for file in `ls -1 $WORKING_DIR/toolchain`
    do
        if [ -d "$WORKING_DIR/toolchain/$file" ]
        then
            if [ $file = "swift-`default-version`" ]
            then
                echo "* ${file#swift\-}"
            else
                echo "- ${file#swift\-}"
            fi
        fi
    done
;;
*)
    echo "Unsupported command: $1"
    exit 3
;;
esac