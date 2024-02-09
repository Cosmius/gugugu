#!/bin/bash

set -e

case "$RUNNER_ARCH" in
	X64|ARM64)
		;;
	*)
		echo "Unexpected RUNNER_ARCH=$RUNNER_ARCH"
		exit 1
		;;
esac

case "$RUNNER_OS" in
	Linux|macOS)
		STACK_ROOT="$GITHUB_WORKSPACE/build/stack"
		UNIX_STACK_ROOT="$STACK_ROOT"
		STACK_BIN="$STACK_ROOT/bin"
		;;
	Windows)
		STACK_ROOT="$GITHUB_WORKSPACE\\build\\stack"
		UNIX_STACK_ROOT=$(cygpath --unix $STACK_ROOT)
		STACK_BIN="$STACK_ROOT\\bin"
		;;
	*)
		echo "Unexpected RUNNER_OS=$RUNNER_OS"
		exit 1
		;;
esac

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
