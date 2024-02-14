.PHONY: build gugugu clean

gugugu_dir := $(abspath $(CURDIR)/../../gugugu)


build: gugugu
	echo "Building example for Python"
	echo "Using python3 at $(shell which python3)"
	python3 --version
	pip install --upgrade .

gugugu:
	gugugu-python \
		--input=$(gugugu_dir) \
		--output=gugugu-generated \
		--package-prefix=guguguexamples.definitions \
		--with-codec \
		--with-server \
		--with-client \
		;

clean:
	pip uninstall --yes gugugu-python-example
	rm -rf build
	rm -rf gugugu-generated
