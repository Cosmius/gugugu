.PHONY: help build docs build-examples test-examples clean

export STACK_BUILD_OPTIONS=--pedantic

help:
	@echo "Please read Makefile for available commands"

build:
	stack build $(STACK_BUILD_OPTIONS)

docs:
	$(MAKE) -C docs html

build-examples:
	$(MAKE) -C examples/lang/haskell build
	$(MAKE) -C examples/lang/python build
	$(MAKE) -C examples/lang/scala build
	$(MAKE) -C examples/lang/rust build
	$(MAKE) -C examples/lang/typescript build

test-examples:
	python3 scripts/test_examples.py -vvv

clean:
	stack clean --full
	make -C docs clean
	$(MAKE) -C examples/lang/haskell clean
	$(MAKE) -C examples/lang/python clean
	$(MAKE) -C examples/lang/scala clean
	$(MAKE) -C examples/lang/rust clean
	$(MAKE) -C examples/lang/typescript clean
