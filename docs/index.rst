Welcome to Gugugu's documentation!
==================================

Gugugu is a non-opinionated data serialization and RPC (Remote Procedure Call)
framework.
*Non-opinionated* means gugugu assumes very little on your implementation.
You can serialize your data with JSON, XML... or your own serialization format,
and communicate with any protocol you like.

The definition syntax is a strict subset of Haskell.

.. literalinclude:: ./examples/Hello.pg
   :language: haskell

There are prebuilt binaries available at
https://bitbucket.org/Cosmius/gugugu/downloads/


.. |all_ci| image:: https://dev.azure.com/cosmiafu/gugugu/_apis/build/status/gugugu?branchName=master
   :target: https://dev.azure.com/cosmiafu/gugugu/_build
   :alt: Azure Pipeline status

.. |linux_ci| image:: https://dev.azure.com/cosmiafu/gugugu/_apis/build/status/gugugu?branchName=master&jobName=build&configuration=build%20linux
   :alt: Azure Pipeline status for Linux

.. |darwin_ci| image:: https://dev.azure.com/cosmiafu/gugugu/_apis/build/status/gugugu?branchName=master&jobName=build&configuration=build%20darwin
   :alt: Azure Pipeline status for macOS

.. |win32_ci| image:: https://dev.azure.com/cosmiafu/gugugu/_apis/build/status/gugugu?branchName=master&jobName=build&configuration=build%20win32
   :alt: Azure Pipeline status for Windows


+---------+-------+-------------+
| All     |       | |all_ci|    |
+---------+-------+-------------+
| Windows | amd64 | |win32_ci|  |
+---------+-------+-------------+
| macOS   | amd64 | |darwin_ci| |
+---------+-------+-------------+
| Linux   | amd64 | |linux_ci|  |
+---------+-------+-------------+


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
