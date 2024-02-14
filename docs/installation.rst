Install Gugugu
==============

Prerequisites
-------------

Gugugu has only several executables with very few dependencies.

* Linux: libgmp.so.10
* Windows: no additional dependencies.
* macOS: no additional dependencies.

Use Prebuilt Binaries
---------------------

* Download the package for your operating system at
  https://github.com/Cosmius/gugugu/releases .
* Unpack the archive and put the executables to somewhere in your ``PATH``.
  You can pick only the target you need, they are all independent from others.

Build from Source
-----------------

Gugugu is written with Haskell.

* Download and install stack,
  which is available at https://www.haskellstack.org/ .
* Run ``stack --local-bin-path=DESTINATION_DIR install``.
