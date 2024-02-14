#!/usr/bin/env bash

set -e

case "$RUNNER_OS" in
	Linux)
		STACK_ROOT="$GITHUB_WORKSPACE/build/stack"
		UNIX_STACK_ROOT="$STACK_ROOT"
		GUGUGU_OS=linux
		;;
	macOS)
		STACK_ROOT="$GITHUB_WORKSPACE/build/stack"
		UNIX_STACK_ROOT="$STACK_ROOT"
		GUGUGU_OS=darwin
		;;
	Windows)
		STACK_ROOT="$GITHUB_WORKSPACE\\build\\stack"
		UNIX_STACK_ROOT=$(cygpath --unix $STACK_ROOT)
		GUGUGU_OS=win32
		mkdir -p $UNIX_STACK_ROOT
		echo "local-programs-path: $STACK_ROOT\\programs" > $UNIX_STACK_ROOT/config.yaml
		;;
	*)
		GUGUGU_OS=unknown-$RUNNER_OS
		echo "Unexpected RUNNER_OS=$RUNNER_OS, don't be suprised if it breaks"
		;;
esac

case "$RUNNER_ARCH" in
	X64)
		GUGUGU_ARCH=amd64
		;;
	ARM64)
		GUGUGU_ARCH=aarch64
		;;
	*)
		GUGUGU_ARCH=unknown-$RUNNER_ARCH
		echo "Unexpected RUNNER_ARCH=$RUNNER_ARCH, don't be suprised if it breaks"
		;;
esac

if [ "$GUGUGU_OS-$GUGUGU_ARCH" = win32-aarch64 ]; then
	echo "$GUGUGU_OS-$GUGUGU_ARCH is not supported, don't be suprised if it breaks"
fi

echo "Using STACK_ROOT = $STACK_ROOT"
echo "STACK_ROOT=$STACK_ROOT" >> "$GITHUB_ENV"
echo "STACK_ROOT=$STACK_ROOT" >> "$GITHUB_OUTPUT"

echo "Using UNIX_STACK_ROOT = $UNIX_STACK_ROOT"
echo "UNIX_STACK_ROOT=$UNIX_STACK_ROOT" >> "$GITHUB_ENV"

STACK_RESOLVER=$(grep -e "^resolver:" stack.yaml | xargs echo | cut -d " " -f 2)
echo "Using STACK_RESOLVER = $STACK_RESOLVER"
echo "STACK_RESOLVER=$STACK_RESOLVER" >> "$GITHUB_ENV"

GUGUGU_VERSION=$(grep -e "version:" hpack-common.yaml | xargs echo | cut -d " " -f 2)
echo "Using GUGUGU_VERSION = $GUGUGU_VERSION"
echo "GUGUGU_VERSION=$GUGUGU_VERSION" >> "$GITHUB_ENV"

echo "Using GUGUGU_OS = $GUGUGU_OS"
echo "GUGUGU_OS=$GUGUGU_OS" >> "$GITHUB_ENV"

echo "Using GUGUGU_ARCH = $GUGUGU_ARCH"
echo "GUGUGU_ARCH=$GUGUGU_ARCH" >> "$GITHUB_ENV"
