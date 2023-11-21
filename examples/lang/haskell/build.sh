#!/bin/bash

set -e

THIS_FILE=${BASH_SOURCE[0]}
if echo $THIS_FILE | grep -q -e "^[^/]"
then
	THIS_FILE="$PWD/$THIS_FILE"
fi

THIS_DIR=$(dirname $THIS_FILE)
cd $THIS_DIR

echo "Building example for haskell"

echo "Using stack at $(which stack):"
stack --version

bash run-gugugu.sh

stack build gugugu-haskell-example --pedantic
