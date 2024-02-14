# Gugugu

[![Build](https://github.com/Cosmius/gugugu/actions/workflows/build.yaml/badge.svg?branch=master)](https://github.com/Cosmius/gugugu/actions/workflows/build.yaml)

Gugugu is a non-opinionated data serialization and RPC (Remote Procedure Call)
framework.
*Non-opinionated* means gugugu assumes very little on your implementation.
You can serialize your data with JSON, XML... or your own serialization format,
and communicate with any protocol you like.

The definition syntax is a strict subset of Haskell.

```haskell
module Hello where


-- The content after double-dash is ignored.

fold :: FoldRequest -> IO Int32

data FoldRequest
  = FoldRequest
    { values  :: List Int32
    , initial :: Int32
    , op      :: Operation
    }

data Operation
  = Add
  | Mul
```

## Documentation

* [Document on readthedocs](https://gugugu.readthedocs.io/en/latest/)
