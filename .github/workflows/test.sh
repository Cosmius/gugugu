#!/bin/bash

set -e

case "$GUGUGU_OS" in
	win32)
		function python3 () {
			python $@
		}
		LOCAL_INSTALL_ROOT=$(cygpath -u $(stack path --local-install-root))
		echo "Using Python at $(which python):"
		;;
	*)
		LOCAL_INSTALL_ROOT=$(stack path --local-install-root)
		echo "Using Python at $(which python3):"
		;;
esac

export PATH=$LOCAL_INSTALL_ROOT/bin:$PATH

python3 --version

python3 -m pip install -U pip setuptools wheel
python3 -m pip install -r scripts/requirements.txt

bash examples/lang/haskell/build.sh
bash examples/lang/scala/build.sh
bash examples/lang/rust/build.sh
bash examples/lang/typescript/build.sh
bash examples/lang/python/build.sh

python3 scripts/test_examples.py -vvv
