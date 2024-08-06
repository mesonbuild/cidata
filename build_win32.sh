#!/bin/bash

REQUIRED=(wget curl sed zip unzip)

BUILD_DIR=build_data
DOWNLOAD_DIR=$BUILD_DIR/downloads
ARCHIVE_DIR=$BUILD_DIR/ci_data
OUT=$BUILD_DIR/ci_data.zip

boost_version='1.72.0'
boost_abi_tag='14.1'

errors=0

# Go to the root dir
cd "$(dirname "$0")"

error() { echo -e "\x1b[31;1mERROR:\x1b[37m $*\x1b[0m"; (( errors++ )); }
msg()   { echo -e "\x1b[32;1m==> \x1b[37m$*\x1b[0m"; }
exit_on_error() { (( errors > 0 )) && exit 1; }
die()   { error "$*"; exit 1; }

check_programs() {
  local i errors
  errors=0
  for i in "${REQUIRED[@]}"; do
    type -P $i &> /dev/null || error "Missing program $i"
  done
  exit_on_error
}

setup_build_dir() {
  msg "Build dir is '$BUILD_DIR'"
  [ -e $BUILD_DIR ] && rm -rf $BUILD_DIR
  mkdir $BUILD_DIR
  mkdir $DOWNLOAD_DIR
  mkdir $ARCHIVE_DIR
}

add() {
  [ ! -e "$1" ] && die "$1 does not exist"
  cp --recursive "$1" "$ARCHIVE_DIR"
}

download() {
  msg "Downloading '$1' from '$2'"
  wget $2 -O $DOWNLOAD_DIR/$1 -q --show-progress || die "Download failed" # &> /dev/null
}

download_add() {
  download "$1" "$2"
  add "$DOWNLOAD_DIR/$1"
}

extract() {
  unzip "$DOWNLOAD_DIR/$1" -d $DOWNLOAD_DIR &> /dev/null
}

configure_install() {
  [ ! -e $BUILD_DIR/install.ps1 ] && cp win32/install.ps1 $BUILD_DIR
  sed -i "s/@$1@/$2/g" $BUILD_DIR/install.ps1
}


main() {
  check_programs
  setup_build_dir

  b_name="${boost_version//./_}"

  # Ninja
  download ninja.zip https://github.com/ninja-build/ninja/releases/download/v1.10.0/ninja-win.zip
  extract  ninja.zip
  add      $DOWNLOAD_DIR/ninja.exe

  # DmD
  dmd_version="$(curl http://downloads.dlang.org/releases/LATEST 2>/dev/null)"
  dmd_url="http://downloads.dlang.org/releases/2.x/$dmd_version/dmd.$dmd_version.windows.zip"
  download dmd.zip "$dmd_url"
  extract  dmd.zip
  add      $DOWNLOAD_DIR/dmd2

  download_add msmpisdk.msi    https://download.microsoft.com/download/D/B/B/DBB64BA1-7B51-43DB-8BF1-D1FB45EACF7A/msmpisdk.msi
  download_add MSMpiSetup.exe  https://download.microsoft.com/download/D/B/B/DBB64BA1-7B51-43DB-8BF1-D1FB45EACF7A/MSMpiSetup.exe
  download_add LLVM.exe        https://github.com/llvm/llvm-project/releases/download/llvmorg-18.1.8/LLVM-18.1.8-win64.exe
  #download_add boost32.exe     https://sourceforge.net/projects/boost/files/boost-binaries/$boost_version/boost_$b_name-msvc-$boost_abi_tag-32.exe
  #download_add boost64.exe     https://sourceforge.net/projects/boost/files/boost-binaries/$boost_version/boost_$b_name-msvc-$boost_abi_tag-64.exe

  add win32/pkg-config.exe
  add win32/setdllcharacteristics.exe

  configure_install BOOST_FILENAME "$b_name"
  configure_install BOOST_ABI_TAG  "$boost_abi_tag"
  add $BUILD_DIR/install.ps1

  # package
  msg "Creating $OUT"
  old_pwd="$PWD"
  pushd $ARCHIVE_DIR  &> /dev/null
  zip -rq "$old_pwd/$OUT" * || die "Failed to create $OUT"
  popd &> /dev/null
  msg "DONE"
}

main
