#!/bin/bash

set -e

mkdir -p $UNIX_STACK_ROOT

case "$RUNNER_OS" in
	Windows)
		echo "local-programs-path: $STACK_ROOT\\programs" > $UNIX_STACK_ROOT/config.yaml
		;;
	*)
		;;
esac

stack build --copy-bins --pedantic
