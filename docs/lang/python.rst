Target - Python
===============

.. note::

   The Python target should be considered experimental.
   Though the code generated works,
   the future versions might generate code completely different with possible
   static type-checking support,
   because the types of generated code cannot be well-expressed with
   ``typing`` module.


Quick Start
-----------

.. sourcecode:: bash

   gugugu-python \
           --input=dir/containing/gugugu/definitions \
           --output=dir/containing/python/code \
           --package-prefix=some.package.prefix \
           --with-codec \
           --with-server \
           --with-client \
           ;


Module
------

Gugugu module is represented by Python modules, with module name lower-cased,
without underscores.


Types
-----

Primitives
~~~~~~~~~~

+-------------+-----------------+
| Gugugu Type | Python Type     |
+=============+=================+
| ``Unit``    | ``object``      |
+-------------+-----------------+
| ``Bool``    | ``bool``        |
+-------------+-----------------+
| ``Int32``   | ``int``         |
+-------------+-----------------+
| ``Double``  | ``float``       |
+-------------+-----------------+
| ``String``  | ``str``         |
+-------------+-----------------+
| ``Maybe A`` | ``Optional[A]`` |
+-------------+-----------------+
| ``List A``  | ``List[A]``     |
+-------------+-----------------+

Record Type
~~~~~~~~~~~

Record type are represented by ``dataclass``.

.. sourcecode:: haskell

   data Book
     = Book
       { id   :: Int32
       , name :: String
       }

becomes

.. sourcecode:: python

   from dataclasses import dataclass

   @dataclass()
   class Book:
       id: int
       name: str

Enum Type
~~~~~~~~~

Enum type are represented by ``IntEnum``.

.. sourcecode:: haskell

   data Color
     = Red
     | Green
     | Blue

becomes

.. sourcecode:: python

   from enum import IntEnum

   class Color(IntEnum):
       RED = 0
       GREEN = 1
       BLUE = 2

Foreign Type
~~~~~~~~~~~~

.. sourcecode:: haskell

   data DateTime
     {-# FOREIGN python datetime.datetime #-}

Foreign type generates no Python codes.
Gugugu just replaces the ``DateTime`` with the corresponding python type.


Encoder and Decoder
-------------------

All types in this section are located in module
``gugugu.lang.python.runtime.codec`` with default configuration.

The generated codecs have type which cannot be expressed with module ``typing``

.. sourcecode:: python

   Encoder = Callable[[S, A, EncoderImpl[S, R]], S]
   Decoder = Callable[[S, EncoderImpl[S, R]], Tuple[S, A]]

   def encode(a: A, impl: EncoderImpl[S, R], encoder: Encoder) -> R:
       pass


   def decode(r: R, impl: DecoderImpl[S, R], decoder: Decoder) -> A:
       pass


The encoder and decoder type should have a type argument, A,
which should be the type of the type to encode or decode.
But it cannot be expressed well in Python.

The encoders and decoders are defined at:

+-------------------+-----------------+-------------------------------------+-------------------------------------+
| Gugugu Type       | Python Type     | Encoder                             | Decoder                             |
+===================+=================+=====================================+=====================================+
| ``Unit``          | ``object``      | ``Encoders.encode_unit``            | ``Decoders.decode_unit``            |
+-------------------+-----------------+-------------------------------------+-------------------------------------+
| ``Bool``          | ``bool``        | ``Encoders.encode_bool``            | ``Decoders.decode_bool``            |
+-------------------+-----------------+-------------------------------------+-------------------------------------+
| ``Int32``         | ``int``         | ``Encoders.encode_int32``           | ``Decoders.decode_int32``           |
+-------------------+-----------------+-------------------------------------+-------------------------------------+
| ``Double``        | ``float``       | ``Encoders.encode_double``          | ``Decoders.decode_double``          |
+-------------------+-----------------+-------------------------------------+-------------------------------------+
| ``String``        | ``str``         | ``Encoders.encode_string``          | ``Decoders.decode_string``          |
+-------------------+-----------------+-------------------------------------+-------------------------------------+
| ``Maybe A``       | ``Optional[A]`` | ``Encoders.encode_maybe(encoderA)`` | ``Decoders.decode_maybe(decoderA)`` |
+-------------------+-----------------+-------------------------------------+-------------------------------------+
| ``List A``        | ``List[A]``     | ``Encoders.encode_list(encoderA)``  | ``Decoders.decode_list(decoderA)``  |
+-------------------+-----------------+-------------------------------------+-------------------------------------+
| ``Foo``           | ``Foo``         | ``Foo.encode_foo``                  | ``Foo.decode_foo``                  |
+-------------------+-----------------+-------------------------------------+-------------------------------------+
| ``Foo`` (foreign) | (foreign)       | ``FooCodec.encode_foo``             | ``FooCodec.decode_foo``             |
+-------------------+-----------------+-------------------------------------+-------------------------------------+

The ``EncoderImpl[S, R]`` and ``DecoderImpl[S, R]`` are two values you have to
provide to describe how to encode and decode a value.

Use the ``encode`` to encode a value of type ``A`` to type ``R``,
with the encoder and the ``EncoderImpl[S, R]``.
Likewise, use the ``decode`` to decode a value of type ``A`` from type ``R``,
with the decoder and the ``DecoderImpl[S, R]``.

The encoder and decoder are polymorphic over ``S`` and ``R``.
With different ``EncoderImpl``/``DecoderImpl`` provided,
you can encode/decode values to/from different types you want.

EncoderImpl and DecoderImpl
~~~~~~~~~~~~~~~~~~~~~~~~~~~

The ``S`` is the state used in encoding/decoding.
The ``R`` is the serialized type encoding to or decoding from.

You might find
:gugugu-source:`examples/lang/python/src/guguguexamples/codec/json.py`
useful to write a ``EncoderImpl``/``DecoderImpl``.

Most functions in the types works with only ``S`` except the following two.

.. sourcecode:: python

   class EncoderImpl(Generic[S, R]):

       @abstractmethod
       def encode_with_state(self, k: Callable[[S], S]) -> R:
           raise NotImplementedError

   class DecoderImpl(Generic[S, R]):

       @abstractmethod
       def decode_with_state(self, r: R, k: Callable[[S], Tuple[S, A]]) -> A:
           raise NotImplementedError


For an ``EncoderImpl.encode_with_state``, you usually should

* Provide an initial state
* Feed it to the function provided
* Transform the state returned to serialized type, ``R``

For a ``DecoderImpl.decode_with_state``, you usually should

* Transform the ``R`` into an initial state ``S``
* Feed it to the function provided
* Make sure the returned state did not go wrong
* Return the decoded value returned by the function provided.

The generated encoders/decoders are designed to be compatible with
either an immutable state type or a mutable one.
The state object will never be reused in generated code.
The modification can happen in place if you take care of it in your code.

The generated code will never throw any exceptions,
but you usually want to do so in your ``EncoderImpl``/``DecoderImpl`` when
things go wrong.

Encode/Decode Record Type
~~~~~~~~~~~~~~~~~~~~~~~~~

.. sourcecode:: python

   class EncoderImpl(Generic[S, R]):

       @abstractmethod
       def encode_record(self, s: S, n_fields: int, k: Callable[[S], S]) -> S:
           raise NotImplementedError

       @abstractmethod
       def encode_record_field(self, s: S,
                               i: int, name: str,
                               k: Callable[[S], S]) -> S:
           raise NotImplementedError

   class DecoderImpl(Generic[S, R]):

       @abstractmethod
       def decode_record(self, s: S, n_fields: int,
                         k: Callable[[S], Tuple[S, A]]) -> Tuple[S, A]:
           raise NotImplementedError

       @abstractmethod
       def decode_record_field(self, s: S,
                               i: int, name: str,
                               k: Callable[[S], Tuple[S, A]]) -> Tuple[S, A]:
           raise NotImplementedError

The generated encoder/decoder for record type consists of a call to
``EncoderImpl.encode_record``/``DecoderImpl.decode_record``.
And the provided callback will call the
``EncoderImpl.encode_record_field``/``DecoderImpl.decode_record_field``
several times with indices and names of the fields.

Encode/Decode Enum Type
~~~~~~~~~~~~~~~~~~~~~~~

.. sourcecode:: python

   class EncoderImpl(Generic[S, R]):

       @abstractmethod
       def encode_enum(self, s: S, a: A,
                       as_index: Callable[[A], int],
                       as_name: Callable[[A], str]) -> S:
           raise NotImplementedError

   class DecoderImpl(Generic[S, R]):

       @abstractmethod
       def decode_enum(self, s: S,
                       by_index: Callable[[int], Optional[A]],
                       by_name: Callable[[str], Optional[A]]) -> Tuple[S, A]:
           raise NotImplementedError

The generated encoder/decoder for enum type consists of a call to
``EncoderImpl.encode_enum``/``DecoderImpl.decode_enum``.
You should encode/decode the value with the name or the index.

Encode/Decode Primitive and Foreign Types
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. sourcecode:: python

   class EncoderImpl(Generic[S, R]):

       @abstractmethod
       def encode_unit(self, s: S, v: object) -> S:
           raise NotImplementedError

       @abstractmethod
       def encode_bool(self, s: S, v: bool) -> S:
           raise NotImplementedError

       @abstractmethod
       def encode_int32(self, s: S, v: int) -> S:
           raise NotImplementedError

       @abstractmethod
       def encode_double(self, s: S, v: float) -> S:
           raise NotImplementedError

       @abstractmethod
       def encode_string(self, s: S, v: str) -> S:
           raise NotImplementedError

       @abstractmethod
       def encode_maybe(self, s: S, v: Optional[A], k: Callable[[S, A], S]) -> S:
           raise NotImplementedError

       @abstractmethod
       def encode_list(self, s: S, v: List[A], k: Callable[[S, A], S]) -> S:
           raise NotImplementedError

   class DecoderImpl(Generic[S, R]):

       @abstractmethod
       def decode_unit(self, s: S) -> Tuple[S, object]:
           raise NotImplementedError

       @abstractmethod
       def decode_bool(self, s: S) -> Tuple[S, bool]:
           raise NotImplementedError

       @abstractmethod
       def decode_int32(self, s: S) -> Tuple[S, int]:
           raise NotImplementedError

       @abstractmethod
       def decode_double(self, s: S) -> Tuple[S, float]:
           raise NotImplementedError

       @abstractmethod
       def decode_string(self, s: S) -> Tuple[S, str]:
           raise NotImplementedError

       @abstractmethod
       def decode_maybe(self, s: S,
                        k: Callable[[S], Tuple[S, A]]) -> Tuple[S, Optional[A]]:
           raise NotImplementedError

       @abstractmethod
       def decode_list(self, s: S,
                       k: Callable[[S], Tuple[S, A]]) -> Tuple[S, List[A]]:
           raise NotImplementedError

The primitive types and foreign types will generate functions like above.
And the encoder/decoder simply calls the function you provide.

The ``Maybe`` and ``List`` functions is also provided with the encoder/decoder
of the parameter type.


Client and Server
-----------------

All types in this section are located in package
``gugugu.lang.python.runtime.transport`` with default configuration.

.. sourcecode:: haskell

   module Hello where

   foo :: FooReq -> IO FooRes
   bar :: BarReq -> IO BarRes

becomes

.. sourcecode:: python

   class HelloModule(ABC):

       @abstractmethod
       def foo(self, fa):
           raise NotImplementedError

       @abstractmethod
       def bar(self, fa):
           raise NotImplementedError

       @classmethod
       def to_transport(cls, impl: HelloModule, decoder_impl, encoder_impl) -> ServerTransport:
           pass

       @classmethod
       def from_transport(cls, transport, encoder_impl, decoder_impl) -> HelloModule:
           pass

The ``HelloModule`` can be used as the client when used in client code,
or as the server implementation in server code.

The ``fa`` should be a type about the incoming type,
usually a tuple of metadata and the incoming value or something similar.
The return type should be a type about the outgoing type,
you can also use ``async`` functions.

Given the incoming type of the function as ``A``,
the outgoing type of the function ``IO B``.

The type of ``fa`` can be

- ``A``, simply itself.
- ``Tuple[SomeMeta, A]``, where ``SomeMeta`` is some metadata.
- ``List[A]``, when you want to process many data in one request.

or their combination decnoted by ``F[A]`` later.

The return type can be

- ``A``, simply itself.
- ``Tuple[SomeMeta, A]``, where ``SomeMeta`` is some metadata.
- ``Future[A]``, if used with ``concurrent.futures``
- ``Awaitable[A]``, if ``async`` function is used.
- ``Callable[[Callable[[A], None]], None]``, if used with continuation.

or their combination, decnoted by ``G[B]`` later.

Of course you have many choices, but be sure use only one not mixed of them.

.. warning::

   Do *not* use any type that contains more than one values of the
   corresponding type if you want to work with other target that does not
   support it.
   And most targets do not support it.


Server Usage
~~~~~~~~~~~~

.. sourcecode:: python

   @dataclass()
   class QualName(Generic[A]):
       namespace: List[A]
       name: A

   class ServerTransport(ABC):
       """ The type of this handler cannot be expressed in Python.
           Haskell notation:

           type ServerCodecHandler f g m ra rb =
               forall a b. (ra -> a)           -- ^ request decoder
                        -> (b -> rb)           -- ^ response encoder
                        -> (f a -> m (g b))    -- ^ request handler
                        -> f ra                -- ^ request encoded
                        -> m (g rb)            -- ^ response encoded
           type ServerTransport f g m ra rb = QualName String
                                           -> ServerCodecHandler f g m ra rb
                                           -> Maybe (f ra -> m (g rb))
       """
       @abstractmethod
       def ask(self, name: QualName[str], k):
           """ The self is expected to be type: ServerTransport f g m ra rb
               The k is expected to be type: ServerCodecHandler f g m ra rb
           """
           raise NotImplementedError

   class HelloModule(ABC):

       @classmethod
       def to_transport(cls, impl: HelloModule, decoder_impl, encoder_impl) -> ServerTransport:
           pass

``HelloModule.to_transport`` converts a ``HelloModule`` into
a ``ServerTransport``.
``ServerTransport.ask`` returns a handler with given name or ``None`` if no
matching handler can be found.
The handler has type ``Callable[[F[RA], G[RB]]``.
The ``decoder_impl`` should be a type of ``DecoderImpl[SA, RA]`` where ``RA``
is the type of the handler accepts.
The ``encoder_impl`` should be a type of ``EncoderImpl[SB, RB]`` where ``RB``
is the type of the handler returns.


The ``k`` required by ``ServerTransport.ask`` is a callback to handle
decoding and encoding.
It should have type

.. sourcecode:: python

   def handle_encoding(decode_request: Callable[[RA], A],
                       encode_response: Callable[[B], RB],
                       handler: Callable[[F[A]], G[B]],
                       fr: F[RA]):
       pass

The decoding function and the encoding function may throw exceptions if you do
that in the corresponding ``EncoderImpl``/``DecoderImpl``,
and you are responsible to handle that.
The function should be polymorphic over type ``A`` and ``B``.

Please consult
:gugugu-source:`examples/lang/python/src/guguguexamples/jsonhttp/server.py`
for how to use the it.

Client Usage
~~~~~~~~~~~~

.. sourcecode:: python

   @dataclass()
   class QualName(Generic[A]):
       namespace: List[A]
       name: A

   class ClientTransport(ABC):
       """ The type of this handler cannot be expressed in Python.
           Haskell notation:

           type ClientTransport f g m ra rb =
               forall a b. QualName String
                        -> (a -> ra)
                        -> (rb -> b)
                        -> f a
                        -> m (g b)
       """
       @abstractmethod
       def send(self, name: QualName[str], encoder, decoder, fa):
           raise NotImplementedError

   class HelloModule(ABC):

       @classmethod
       def from_transport(cls, transport, encoder_impl, decoder_impl) -> HelloModule:
           pass

``HelloModule.from_transport`` converts a ``ClientTransport``
into a ``HelloModule``.
Like ``ServerTransport``, it can handle request about type ``RA``
and return an response about type ``RB``.
Like ``ServerCodecHandler``, you are responsible to handle possible exceptions.

Please consult
:gugugu-source:`examples/lang/python/src/guguguexamples/jsonhttp/client.py`
for how to write a ``ClientTransport``.


Command Line Options
--------------------

.. sourcecode:: none

   Usage: gugugu-python (-i|--input INPUT) (-o|--output OUTPUT)
                        (-p|--package-prefix PACKAGE_PREFIX)
                        [-r|--runtime-package RUNTIME_PACKAGE] [--with-codec]
                        [--with-server] [--with-client] [--trans-module-code ARG]
                        [--trans-module-value ARG] [--trans-module-type ARG]
                        [--trans-func-code ARG] [--trans-func-value ARG]
                        [--trans-type-code ARG] [--trans-type-func ARG]
                        [--trans-field-code ARG] [--trans-field-value ARG]
                        [--trans-enum-code ARG] [--trans-enum-value ARG]
                        [--version]

   Available options:
     -i,--input INPUT         the directory containing the definition files
     -o,--output OUTPUT       the directory to put the generated sources
     -p,--package-prefix PACKAGE_PREFIX
                              the package prefix, e.g. some.package.prefix
     -r,--runtime-package RUNTIME_PACKAGE
                              location of gugugu runtime
                              package (default: "gugugu.lang.python.runtime")
     --with-codec             pass this flag to generate codecs, default to false
     --with-server            pass this flag to generate server, default to false,
                              implies with-codec
     --with-client            pass this flag to generate client, default to false,
                              implies with-codec
     --trans-module-code ARG  module name transformer for code (default: lower)
     --trans-module-value ARG module name transformer for value (default: snake)
     --trans-module-type ARG  module name transformer for type of
                              client/server (default: id)
     --trans-func-code ARG    function name transformer for code (default: snake)
     --trans-func-value ARG   function name transformer for value (default: snake)
     --trans-type-code ARG    type name transformer for code (default: id)
     --trans-type-func ARG    type name transformer in function (default: snake)
     --trans-field-code ARG   record field name transformer for
                              code (default: snake)
     --trans-field-value ARG  record field name transformer for
                              value (default: snake)
     --trans-enum-code ARG    enum name transformer for code (default: upper-snake)
     --trans-enum-value ARG   enum name transformer for
                              value (default: upper-snake)
     -h,--help                Show this help text
     --help-transformers      list available name transformers
     --version                show version
