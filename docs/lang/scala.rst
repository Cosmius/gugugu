Target - Scala
==============

Quick Start
-----------

.. sourcecode:: bash

   gugugu-scala \
           --input=dir/containing/gugugu/definitions \
           --output=dir/containing/scala/code \
           --package-prefix=com.example.foo.generated \
           --with-codec \
           --with-server \
           --with-client \
           --no-higher-kinds-import \
           ;


Module
------

Gugugu module is represented by Scala packages, with module name lower-cased,
without underscores.


Types
-----

Primitives
~~~~~~~~~~

+-------------+---------------+
| Gugugu Type | Scala Type    |
+=============+===============+
| ``Unit``    | ``Unit``      |
+-------------+---------------+
| ``Bool``    | ``Boolean``   |
+-------------+---------------+
| ``Int32``   | ``Int``       |
+-------------+---------------+
| ``Double``  | ``Double``    |
+-------------+---------------+
| ``String``  | ``String``    |
+-------------+---------------+
| ``Maybe A`` | ``Option[A]`` |
+-------------+---------------+
| ``List A``  | ``Vector[A]`` |
+-------------+---------------+

Record Type
~~~~~~~~~~~

Record type are represented by ``case class``.

.. sourcecode:: haskell

   data Book
     = Book
       { id   :: Int32
       , name :: String
       }

becomes

.. sourcecode:: scala

   case class Book
     ( id   : Int32
     , name : String
     )

Enum Type
~~~~~~~~~

Enum type are represented by ``sealed trait``.

.. sourcecode:: haskell

   data Color
     = Red
     | Green
     | Blue

becomes

.. sourcecode:: scala

   sealed trait Color

   object Color {
     case object Red   extends Color
     case object Green extends Color
     case object Blue  extends Color
   }

Foreign Type
~~~~~~~~~~~~

.. sourcecode:: haskell

   data DateTime
     {-# FOREIGN scala java.time.LocalDateTime #-}

Foreign type generates no scala codes.
Gugugu just replaces the ``DateTime`` with the corresponding scala type.


Encoder and Decoder
-------------------

All types in this section are located in package
``gugugu.lang.scala.runtime.codec`` with default configuration.

The generated codecs have type

.. sourcecode:: scala

   trait Encoder[A] {
     def encode[S, R](s: S, a: A, impl: EncoderImpl[S, R]): S
   }

   trait Decoder[A] {
     def decode[S, R](s: S, impl: DecoderImpl[S, R]): (S, A)
   }

   object Encoder {
     def apply[A](implicit encoder: Encoder[A]): Encoder[A]
     def encode[S, R, A](a: A, impl: EncoderImpl[S, R])
                        (implicit encoder: Encoder[A]): R
   }

   object Decoder {
     def apply[A](implicit decoder: Decoder[A]): Decoder[A]
     def decode[S, R, A](r: R, impl: DecoderImpl[S, R])
                        (implicit decoder: Decoder[A]): A
   }

The encoder and decoder are always defined as implicit values of the companion
object,
so you can get them with the expression ``Encoder[A]`` or ``Decoder[A]``.

The ``EncoderImpl[S, R]`` and ``DecoderImpl[S, R]`` are two values you have to
provide to describe how to encode and decode a value.

Use the ``Encoder.encode[S, R, A]`` to encode a value of type ``A`` to type
``R``, with the encoder and the ``EncoderImpl[S, R]``.
Likewise, use the ``Decoder.decode[S, R, A]`` to decode a value of type ``A``
from type ``R``, with the decoder and the ``DecoderImpl[S, R]``.

The encoder and decoder are polymorphic over ``S`` and ``R``.
With different ``EncoderImpl``/``DecoderImpl`` provided,
you can encode/decode values to/from different types you want.

EncoderImpl and DecoderImpl
~~~~~~~~~~~~~~~~~~~~~~~~~~~

The ``S`` is the state used in encoding/decoding.
The ``R`` is the serialized type encoding to or decoding from.

You might find
`examples/lang/scala/src/main/scala/guguguexamples/codec/JsonCodecImpl.scala <https://bitbucket.org/Cosmius/gugugu/src/master/examples/lang/scala/src/main/scala/guguguexamples/codec/JsonCodecImpl.scala>`_
useful to write a ``EncoderImpl``/``DecoderImpl``.

Most functions in the traits works with only ``S`` except the following two.

.. sourcecode:: scala

   trait EncoderImpl[S, R] {
     def encodeWithState(k: S => S): R
   }

   trait DecoderImpl[S, R] {
     def decodeWithState[A](r: R, k: S => (S, A)): A
   }

For an ``EncoderImpl.encodeWithState``, you usually should

* Provide an initial state
* Feed it to the function provided
* Transform the state returned to serialized type, ``R``

For a ``DecoderImpl.decodeWithState``, you usually should

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

.. sourcecode:: scala

   trait EncoderImpl[S, R] {
     def encodeRecord(s: S, nFields: Int, k: S => S): S
     def encodeRecordField( s: S
                          , i: Int, name: String
                          , k: S => S
                          ): S
   }

   trait DecoderImpl[S, R] {
     def decodeRecord[A](s: S, nFields: Int, k: S => (S, A)): (S, A)
     def decodeRecordField[A]( s: S
                             , i: Int, name: String
                             , k: S => (S, A)
                             ): (S, A)
   }

The generated encoder/decoder for record type consists of a call to
``EncoderImpl.encodeRecord``/``DecoderImpl.decodeRecord``.
And the provided callback will call the
``EncoderImpl.encodeRecordField``/``DecoderImpl.decodeRecordField``
several times with indices and names of the fields.

Encode/Decode Enum Type
~~~~~~~~~~~~~~~~~~~~~~~

.. sourcecode:: scala

   trait EncoderImpl[S, R] {
     def encodeEnum[A]( s: S, a: A
                      , asIndex: A => Int
                      , asName: A => String
                      ): S
   }

   trait DecoderImpl[S, R] {
     def decodeEnum[A]( s: S
                      , byIndex: Int => Option[A]
                      , byName: String => Option[A]
                      ): (S, A)
   }

The generated encoder/decoder for enum type consists of a call to
``EncoderImpl.encodeEnum``/``DecoderImpl.decodeEnum``.
You should encode/decode the value with the name or the index.

Encode/Decode Primitive and Foreign Types
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. sourcecode:: scala

   trait EncoderImpl[S, R] {
     def encodeUnit(s: S, v: Unit): S
     def encodeBool(s: S, v: Boolean): S
     def encodeInt32(s: S, v: Int): S
     def encodeDouble(s: S, v: Double): S
     def encodeString(s: S, v: String): S
   }

   trait DecoderImpl[S, R] {
     def decodeUnit(s: S): (S, Unit)
     def decodeBool(s: S): (S, Boolean)
     def decodeInt32(s: S): (S, Int)
     def decodeDouble(s: S): (S, Double)
     def decodeString(s: S): (S, String)
   }

The primitive types and foreign types will generate functions like above.
And the encoder/decoder simply calls the function you provide.

Encode/Decode ``Maybe`` and ``List``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. sourcecode:: scala

   trait EncoderImpl[S, R] {
     def encodeMaybe(s: S, isNothing: Boolean, k: S => S): S

     def encodeList(s: S, len: Int, k: S => S): S
     def encodeListNth(s: S, i: Int, k: S => S): S
   }

   trait DecoderImpl[S, R] {
     def decodeMaybe[A](s: S, k: (S, Boolean) => (S, A)): (S, A)

     def decodeList[A](s: S, k: (S, Int) => (S, A)): (S, A)
     def decodeListNth[A](s: S, i: Int, k: S => (S, A)): (S, A)
   }

The ``List`` functions works like the record functions,
except they do not care about the name.

You have to tell the callback provided by ``DecoderImpl.decodeMaybe``
whether the value is empty or not.

You have to tell the callback provided by ``DecoderImpl.decodeList``
the length of the list.


Client and Server
-----------------

All types in this section are located in package
``gugugu.lang.scala.runtime.transport`` with default configuration.

.. sourcecode:: haskell

   module Hello where

   foo :: FooReq -> IO FooRes
   bar :: BarReq -> IO BarRes

becomes

.. sourcecode:: scala

   trait HelloModule[F[_], G[_], M[_]] {
     def foo(fa: F[FooReq]): M[G[FooRes]]
     def bar(fa: F[BarReq]): M[G[BarRes]]
   }

   object HelloModule {
     def toTransport[F[_], G[_], M[_], RA, RB, SA, SB]( impl: HelloModule[F, G, M]
                                                      , decoderImpl: DecoderImpl[SA, RA]
                                                      , encoderImpl: EncoderImpl[SB, RB]
                                                      ): ServerTransport[F, G, M, RA, RB]

     def fromTransport[F[_], G[_], M[_], RA, RB, SA, SB]( transport: ClientTransport[F, G, M, RA, RB]
                                                        , encoderImpl: EncoderImpl[SA, RA]
                                                        , decoderImpl: DecoderImpl[SB, RB]
                                                        ): HelloModule[F, G, M]
   }

The ``HelloModule`` can be used as the client when used in client code,
or as the server implementation in server code.

The ``RA`` is the serialized type used by request,
and the ``RB`` is the serialized type used by response.
They are usually the same type but not necessary.

Some typical use of ``F``, ``G`` and ``M`` are list below.

``F`` can be

- ``type I[A] = A``, when you just want to pass the value.
- ``type WithMeta[A] = (SomeMeta, A)``, when you want some metadata with your
  request, such as authentication data.
- ``Stream``, when you want to process many data in one request.

``G`` can be

- ``type I[A] = A``, when you just want to pass the value.
- ``type WithMeta[A] = (SomeMeta, A)``, when you want to return some metadata to
  with your response, such as request ID, processed time, etc.
- ``Stream``, when you want to return many data in one request.
- ``Try``. when you want error handling.

``M`` can be

- ``type I[A] = A``, when you want a simple synchronized client or server.
- ``Future``, when you want an asynchronous client or server with ``Future``.
  Note, you can put the ``ExecutionContext`` as the metadata into the function.
- ``type Continuation[A] = (A => Unit) => Unit``,
  when you want a simple callback based service.
- ``cats.effect.IO``, when you want to work with ``cats-effect``.
- ``type ContIO[R, A] = (A => IO[R]) => IO[R]``,
  if you want delimited continuation.
  Vide http://hackage.haskell.org/package/transformers-0.5.6.2/docs/Control-Monad-Trans-Cont.html
  and https://en.wikipedia.org/wiki/Delimited_continuation.

.. warning::

   Do *not* use any type that cannot be converted into
   ``type WithMeta[A] = (SomeMeta, Option[A])`` (such as ``Stream``)
   as ``F`` or ``G`` if you want to work with other target that does not
   support polymorphism over higher-kinded types.
   Most targets do not support polymorphism over higher-kinded types.

Server Usage
~~~~~~~~~~~~

.. sourcecode:: scala

   case class QualName[A](namespace: Vector[A], name: A)

   trait ServerTransport[F[_], G[_], M[_], RA, RB] {
     def ask( name: QualName[String]
            , codecHandler: ServerCodecHandler[F, G, M, RA, RB]
            ): Option[F[RA] => M[G[RB]]]
   }

   trait ServerCodecHandler[F[_], G[_], M[_], RA, RB] {
     def apply[A, B]( fr: F[RA]
                    , decodeA: RA => A
                    , encodeB: B => RB
                    , k: F[A] => M[G[B]]
                    ): M[G[RB]]
   }

``HelloModule.toTransport`` converts a ``HelloModule[F, G, M]`` into
a ``ServerTransport[F, G, M, RA, RB]``.
A ``ServerTransport[F, G, M, RA, RB]`` can handle request about type ``RA``
and return an response about type ``RB``.

To call the ``ServerTransport``,
you need a ``ServerCodecHandler[F, G, M, RA, RB]`` to handle the
encoding/decoding,
because Gugugu only knows how to decode from ``RA`` to ``A``
and encode from ``B`` to ``RB``,
but does not know how to decode from ``F[RA]`` to ``F[A]``
and encode from ``G[B]`` to ``G[RB]``,
and how to handle possible exceptions.
The decoder and the encoder may throw exceptions if you do that in the
corresponding ``EncoderImpl``/``DecoderImpl``,
and you are responsible to handle that.

Please consult
`examples/lang/scala/src/main/scala/guguguexamples/jsonhttp/server/ <https://bitbucket.org/Cosmius/gugugu/src/master/examples/lang/scala/src/main/scala/guguguexamples/jsonhttp/server/>`_
for how to use the ``ServerTransport``.

Client Usage
~~~~~~~~~~~~

.. sourcecode:: scala

   case class QualName[A](namespace: Vector[A], name: A)

   trait ClientTransport[F[_], G[_], M[_], RA, RB] {
     def send[A, B]( name: QualName[String]
                   , fa: F[A]
                   , encodeA: A => RA
                   , decodeB: RB => B
                   ): M[G[B]]
   }

``HelloModule.fromTransport`` converts a ``ClientTransport[F, G, M, RA, RB]``
into a ``HelloModule[F, G, M]``.
Like ``ServerTransport``, it can handle request about type ``RA``
and return an response about type ``RB``.
Like ``ServerCodecHandler``, you are responsible to handle possible exceptions.

Please consult
`examples/lang/scala/src/main/scala/guguguexamples/jsonhttp/client/ <https://bitbucket.org/Cosmius/gugugu/src/master/examples/lang/scala/src/main/scala/guguguexamples/jsonhttp/client/>`_
for how to write a ``ClientTransport``.

Command Line Options
--------------------

.. sourcecode:: none

   Usage: gugugu-scala (-i|--input INPUT) (-o|--output OUTPUT)
                       (-p|--package-prefix PACKAGE_PREFIX)
                       [-r|--runtime-package RUNTIME_PACKAGE] [--with-codec]
                       [--with-server] [--with-client] [--no-higher-kinds-import]
                       [--trans-module-code ARG] [--trans-module-value ARG]
                       [--trans-module-type ARG] [--trans-func-code ARG]
                       [--trans-func-value ARG] [--trans-type-code ARG]
                       [--trans-type-func ARG] [--trans-field-code ARG]
                       [--trans-field-value ARG] [--trans-enum-code ARG]
                       [--trans-enum-value ARG] [--version]

   Available options:
     -i,--input INPUT         the directory containing the definition files
     -o,--output OUTPUT       the directory to put the generated sources
     -p,--package-prefix PACKAGE_PREFIX
                              the package prefix, e.g. com.example.foo.generated
     -r,--runtime-package RUNTIME_PACKAGE
                              location of gugugu runtime package
                              (default: "gugugu.lang.scala.runtime")
     --with-codec             pass this flag to generate codecs, default to false
     --with-server            pass this flag to generate server, default to false,
                              implies with-codec
     --with-client            pass this flag to generate client, default to false,
                              implies with-codec
     --no-higher-kinds-import pass this flag to disable import
                              scala.language.higherKinds, which is not necessary in
                              scala 2.13+
     --trans-module-code ARG  module name transformer for code (default: lower)
     --trans-module-value ARG module name transformer for value (default: snake)
     --trans-module-type ARG  module name transformer for type of client/server
                              (default: id)
     --trans-func-code ARG    function name transformer for code (default: id)
     --trans-func-value ARG   function name transformer for value (default: snake)
     --trans-type-code ARG    type name transformer for code (default: id)
     --trans-type-func ARG    type name transformer in function (default: id)
     --trans-field-code ARG   record field name transformer for code (default: id)
     --trans-field-value ARG  record field name transformer for value
                              (default: snake)
     --trans-enum-code ARG    enum name transformer for code (default: id)
     --trans-enum-value ARG   enum name transformer for value
                              (default: upper-snake)
     -h,--help                Show this help text
     --help-transformers      list available name transformers
     --version                show version
