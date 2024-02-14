.PHONY: build gugugu clean

gugugu_dir := $(abspath $(CURDIR)/../../gugugu)


build: gugugu
	echo "Building example for Rust"
	echo "Using cargo at $(shell which cargo)"
	cargo --version
	cargo build

gugugu:
	gugugu-rust \
		--input=$(gugugu_dir) \
		--output=gugugu-generated \
		--module-prefix=definitions \
		--derives=Debug,PartialEq \
		--with-codec \
		--with-server \
		--with-client \
		;

clean:
	cargo clean
	rm -rf gugugu-generated
