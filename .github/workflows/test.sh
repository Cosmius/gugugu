#!/bin/bash

set -e

case "$GUGUGU_OS" in
	win32)
		LOCAL_INSTALL_ROOT=$(cygpath -u $(stack path --local-install-root))
		;;
	*)
		LOCAL_INSTALL_ROOT=$(stack path --local-install-root)
		;;
esac

export PATH=$LOCAL_INSTALL_ROOT/bin:$PATH

make build-examples

echo "Using Python at $(which python3):"
python3 --version
pip install -U pip setuptools wheel
pip install -r scripts/requirements.txt

make test-examples
