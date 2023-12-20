#!/usr/bin/env bash
# Note: this has to be called from a Dockerfile!

set -eux

whoami
apt-get update
apt-get install -y --no-install-recommends \
  git \
  python3-pip \
  python3-dev \
  pkg-config \
  libreadline-dev \
  readline-common \
  moreutils \
  gawk \
  cc1541 \
  cpmtools \
  libfmt-dev \
  ninja-build \
  fp-compiler 

apt-get clean
rm -rf /var/lib/apt/lists/*

wget https://github.com/llvm-mos/llvm-mos-sdk/releases/latest/download/llvm-mos-linux.tar.xz
sudo tar -xvf llvm-mos-linux.tar.xz -C /opt
rm llvm-mos-linux.tar.xz
 

