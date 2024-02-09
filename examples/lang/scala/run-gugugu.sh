#!/bin/bash

set -e

THIS_FILE=${BASH_SOURCE[0]}
if echo $THIS_FILE | grep -q -e "^[^/]"
then
	THIS_FILE="$PWD/$THIS_FILE"
fi

THIS_DIR=$(dirname $THIS_FILE)
EXAMPLE_DIR=$(dirname $(dirname $THIS_DIR))
SRC_OUTPUT=$THIS_DIR/build/generated/gugugu/main/scala

rm -rf $THIS_DIR/build/generated/gugugu

gugugu-scala \
	--input=$EXAMPLE_DIR/gugugu \
	--output=$SRC_OUTPUT \
	--with-codec \
	--with-server \
	--with-client \
	--no-higher-kinds-import \
	--package-prefix=guguguexamples.definitions \
	;
