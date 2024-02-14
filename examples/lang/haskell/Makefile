.PHONY: build gugugu clean

gugugu_dir := $(abspath $(CURDIR)/../../gugugu)


build: gugugu
	echo "Building example for Haskell"
	echo "Using stack at $(shell which stack)"
	stack --version
	stack build gugugu-haskell-example $(STACK_BUILD_OPTIONS)

gugugu:
	gugugu-haskell \
		--input="$(gugugu_dir)" \
		--output=gugugu-generated \
		--module-prefix=GuguguExamples.Definitions \
		--derivings=Show \
		--with-codec \
		--with-server \
		--with-client \
		;

clean:
	rm -rf .stack-work
	rm -rf gugugu-generated
