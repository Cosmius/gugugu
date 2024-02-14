#!/bin/bash

set -e

ARCHIVE_NAME=gugugu-$GUGUGU_VERSION-$GUGUGU_OS-$GUGUGU_ARCH
PREPARING_DIR=build/preparing/$ARCHIVE_NAME
mkdir -p build/preparing/$ARCHIVE_NAME
stack --local-bin-path=$PREPARING_DIR install

cp core/LICENSE $PREPARING_DIR/LICENSE
mkdir -p build/release
tar -czf build/release/$ARCHIVE_NAME.tar.gz -C build/preparing $ARCHIVE_NAME
