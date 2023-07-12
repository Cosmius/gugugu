#!/bin/bash

set -e

case "$RUNNER_OS" in
	Linux|macOS)
		PYTHON=python3
		LOCAL_INSTALL_ROOT=$(stack path --local-install-root)
		;;
	Windows)
		PYTHON=python
		LOCAL_INSTALL_ROOT=$(cygpath -u $(stack path --local-install-root))
		;;
	*)
		echo "Unexpected RUNNER_OS=$RUNNER_OS"
		exit 1
		;;
esac

export PATH=$LOCAL_INSTALL_ROOT/bin:$PATH

echo "Using Python at $(which $PYTHON):"
$PYTHON --version

$PYTHON -m pip install -U pip setuptools wheel
$PYTHON -m pip install -r scripts/requirements.txt

for EXAMPLE_BUILD in $(ls -d examples/lang/*/build.sh)
do
	bash $EXAMPLE_BUILD
done

$PYTHON scripts/test_examples.py -vvv
