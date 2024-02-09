#!/bin/bash

set -e

ARCHIVE_NAME=gugugu-$GUGUGU_VERSION-$RUNNER_OS-$RUNNER_ARCH
PREPARING_DIR=build/preparing/$ARCHIVE_NAME
mkdir -p build/preparing/$ARCHIVE_NAME
stack $STACK_ARGS --local-bin-path=$PREPARING_DIR install

cp core/LICENSE $PREPARING_DIR/LICENSE
mkdir -p build/release
tar -czf build/release/$ARCHIVE_NAME.tar.gz -C build/preparing $ARCHIVE_NAME
