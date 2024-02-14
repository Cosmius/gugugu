.PHONY: build gugugu clean

gugugu_dir := $(abspath $(CURDIR)/../../gugugu)


build: gugugu
	echo "Building example for Scala"
	echo "Using gradle at $(shell which gradle)"
	gradle -version
	gradle build

gugugu:
	gugugu-scala \
		--input=$(gugugu_dir) \
		--output=gugugu-generated/main/scala \
		--no-higher-kinds-import \
		--package-prefix=guguguexamples.definitions \
		--with-codec \
		--with-server \
		--with-client \
		;

clean:
	gradle clean
	rm -rf gugugu-generated
