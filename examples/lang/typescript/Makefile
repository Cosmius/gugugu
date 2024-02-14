.PHONY: build gugugu clean

gugugu_dir := $(abspath $(CURDIR)/../../gugugu)


build: gugugu
	echo "Building example for TypeScript"
	echo "Using node at $(shell which node)"
	node --version
	echo "Using npm at $(shell which npm)"
	npm --version
	npm install
	npm run build

gugugu:
	gugugu-typescript \
		--input=$(gugugu_dir) \
		--output=gugugu-generated \
		--package-prefix=guguguexamples/definitions \
		--with-codec \
		--with-server \
		--with-client \
		;

clean:
	rm -rf build
	rm -rf gugugu-generated
