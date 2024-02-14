Welcome to Gugugu's documentation!
==================================

.. |github_action_ci| image:: https://github.com/Cosmius/gugugu/actions/workflows/build.yaml/badge.svg?branch=master
   :target: https://github.com/Cosmius/gugugu/actions/workflows/build.yaml
   :alt: GitHub Action Status

|github_action_ci|

Gugugu is a non-opinionated data serialization and RPC (Remote Procedure Call)
framework.
*Non-opinionated* means gugugu assumes very little on your implementation.
You can serialize your data with JSON, XML... or your own serialization format,
and communicate with any protocol you like.

The definition syntax is a strict subset of Haskell.

.. literalinclude:: ./examples/Hello.pg
   :language: haskell

There are prebuilt binaries available at
https://github.com/Cosmius/gugugu/releases


.. toctree::
   :maxdepth: 2
   :caption: Contents

   installation
   syntax
   changes

Targets
-------

.. toctree::
   :maxdepth: 2
   :caption: Targets

   lang/haskell
   lang/python
   lang/rust
   lang/scala
   lang/typescript


Indices and tables
==================

* :ref:`genindex`
* :ref:`modindex`
* :ref:`search`
