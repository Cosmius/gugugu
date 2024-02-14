Target - TypeScript
===================

Quick Start
-----------

.. sourcecode:: bash

   gugugu-typescript \
           --input=dir/containing/gugugu/definitions \
           --output=dir/containing/typescript/code \
           --package-prefix=prefix/of/generated/code \
           --with-codec \
           --with-server \
           --with-client \
           ;


Module
------

Gugugu module is represented by TypeScript modules,
with module name lower-cased, without underscores.


Types
-----

Primitives
~~~~~~~~~~

+-------------+-----------------+
| Gugugu Type | TypeScript Type |
+=============+=================+
| ``Unit``    | ``{}``          |
+-------------+-----------------+
| ``Bool``    | ``boolean``     |
+-------------+-----------------+
| ``Int32``   | ``number``      |
+-------------+-----------------+
| ``Double``  | ``number``      |
+-------------+-----------------+
| ``String``  | ``string``      |
+-------------+-----------------+
| ``Maybe A`` | ``null | A``    |
+-------------+-----------------+
| ``List A``  | ``Array<A>``    |
+-------------+-----------------+

Record Type
~~~~~~~~~~~

Record type are represented by ``class``.

.. sourcecode:: haskell

   data Book
     = Book
       { id   :: Int32
       , name :: String
       }

becomes

.. sourcecode:: typescript

   export class Book {

     public constructor
       ( public id: number,
       , public name: string,
       ) { }

   }

Enum Type
~~~~~~~~~

Enum type are represented by alias of string literals.

.. sourcecode:: haskell

   data Color
     = Red
     | Green
     | Blue

becomes

.. sourcecode:: typescript

   export type Color = "Red" | "Green" | "Blue";

Foreign Type
~~~~~~~~~~~~

.. sourcecode:: haskell

   data DateTime
     {-# FOREIGN typescript "moment".Moment #-}

becomes

.. sourcecode:: typescript

   import * as _gugugu_f_moment from "moment";
   export type DateTime = _gugugu_f_moment.Moment;


Encoder and Decoder
-------------------

All types in this section are located in module
``SOURCE_ROOT/gugugu/codec``.

The generated code is like

.. sourcecode:: typescript

   export type Encoder<A> = <S, R>(s: S, a: A, impl: EncoderImpl<S, R>) => S;

   export type Decoder<A> = <S, R>(s: S, impl: DecoderImpl<S, R>) => [S, A];

   class _Encoder {
     public encode<S, R, A>( a: A, impl: EncoderImpl<S, R>
                           , encoder: Encoder<A>): R;
   }

   export const Encoder = new _Encoder();

   class _Encoder {
     public decode<S, R, A>( r: R, impl: DecoderImpl<S, R>
                           , decoder: Decoder<A>): A;
   }

   export const Decoder = new _Decoder();

The encoders and decoders are defined at:

+-------------+-----------------+-----------------------------+-----------------------------+
| Gugugu Type | TypeScript Type | Encoder                     | Decoder                     |
+=============+=================+=============================+=============================+
| ``Unit``    | ``{}``          | ``Encoder.unit``            | ``Decoder.unit``            |
+-------------+-----------------+-----------------------------+-----------------------------+
| ``Bool``    | ``boolean``     | ``Encoder.bool``            | ``Decoder.bool``            |
+-------------+-----------------+-----------------------------+-----------------------------+
| ``Int32``   | ``number``      | ``Encoder.int32``           | ``Decoder.int32``           |
+-------------+-----------------+-----------------------------+-----------------------------+
| ``Double``  | ``number``      | ``Encoder.double``          | ``Decoder.double``          |
+-------------+-----------------+-----------------------------+-----------------------------+
| ``String``  | ``string``      | ``Encoder.string``          | ``Decoder.string``          |
+-------------+-----------------+-----------------------------+-----------------------------+
| ``Maybe A`` | ``null | A``    | ``Encoder.maybe(encoderA)`` | ``Decoder.maybe(decoderA)`` |
+-------------+-----------------+-----------------------------+-----------------------------+
| ``List A``  | ``Array<A>``    | ``Encoder.list(encoderA)``  | ``Decoder.list(decoderA)``  |
+-------------+-----------------+-----------------------------+-----------------------------+
| ``Foo``     | ``Foo``         | ``Foo.encodeFoo``           | ``Foo.decodeFoo``           |
+-------------+-----------------+-----------------------------+-----------------------------+

The ``EncoderImpl<S, R>`` and ``DecoderImpl<S, R>`` are two values you have to
provide to describe how to encode and decode a value.

Use the ``Encoder.encode<S, R, A>`` to encode a value of type ``A`` to type
``R``, with the encoder and the ``EncoderImpl<S, R>``.
Likewise, use the ``Decoder.decode<S, R, A>`` to decode a value of type ``A``
from type ``R``, with the decoder and the ``DecoderImpl<S, R>``.

The encoder and decoder are polymorphic over ``S`` and ``R``.
With different ``EncoderImpl``/``DecoderImpl`` provided,
you can encode/decode values to/from different types you want.

EncoderImpl and DecoderImpl
~~~~~~~~~~~~~~~~~~~~~~~~~~~

The ``S`` is the state used in encoding/decoding.
The ``R`` is the serialized type encoding to or decoding from.

You might find
:gugugu-source:`examples/lang/typescript/src/codec/json-codec.ts`
useful to write a ``EncoderImpl``/``DecoderImpl``.

Most functions in the interfaces works with only ``S`` except the following two.

.. sourcecode:: typescript

   export interface EncoderImpl<S, R> {
     encodeWithState(k: (s: S) => S): R;
   }

   export interface DecoderImpl<S, R> {
     decodeWithState<A>(r: R, k: (s: S) => [S, A]): A;
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

.. sourcecode:: typescript

   export interface EncoderImpl<S, R> {
     encodeRecord(s: S, nFields: number, k: (s: S) => S): S;
     encodeRecordField( s: S, i: number
                      , name: string
                      , k: (s: S) => S
                      ): S;
   }

   export interface DecoderImpl<S, R> {
     decodeRecord<A>(s: S, nFields: number, k: (s: S) => [S, A]): [S, A];
     decodeRecordField<A>( s: S, i: number
                         , name: string
                         , k: (s: S) => [S, A]
                         ): [S, A];
   }

The generated encoder/decoder for record type consists of a call to
``EncoderImpl.encodeRecord``/``DecoderImpl.decodeRecord``.
And the provided callback will call the
``EncoderImpl.encodeRecordField``/``DecoderImpl.decodeRecordField``
several times with indices and names of the fields.

Encode/Decode Enum Type
~~~~~~~~~~~~~~~~~~~~~~~

.. sourcecode:: typescript

   export interface EncoderImpl<S, R> {
     encodeEnum<A>( s: S, a: A
                  , asIndex: (a: A) => number
                  , asName: (a: A) => string
                  ): S;
   }

   export interface DecoderImpl<S, R> {
     decodeEnum<A>( s: S
                  , byIndex: (i: number) => null | A
                  , byName: (n: string) => null | A
                  ): [S, A];
   }

The generated encoder/decoder for enum type consists of a call to
``EncoderImpl.encodeEnum``/``DecoderImpl.decodeEnum``.
You should encode/decode the value with the name or the index.

Encode/Decode Primitive and Foreign Types
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. sourcecode:: typescript

   export interface EncoderImpl<S, R> {
     encodeUnit(s: S, v: {}): S;
     encodeBool(s: S, v: boolean): S;
     encodeInt32(s: S, v: number): S;
     encodeDouble(s: S, v: number): S;
     encodeString(s: S, v: string): S;
   }

   export interface DecoderImpl<S, R> {
     decodeUnit(s: S): [S, {}];
     decodeBool(s: S): [S, boolean];
     decodeInt32(s: S): [S, number];
     decodeDouble(s: S): [S, number];
     decodeString(s: S): [S, string];
   }

The primitive types and foreign types will generate functions like above.
And the encoder/decoder simply calls the function you provide.

Encode/Decode ``Maybe`` and ``List``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. sourcecode:: typescript

   export interface EncoderImpl<S, R> {
     encodeMaybe(s: S, isNothing: boolean, k: (s: S) => S): S;

     encodeList(s: S, len: number, k: (s: S) => S): S;
     encodeListNth(s: S, i: number, k: (s: S) => S): S;
   }

   export interface DecoderImpl<S, R> {
     decodeMaybe<A>(s: S, k: (s: S, isNothing: boolean) => [S, A]): [S, A];

     decodeList<A>(s: S, k: (s: S, len: number) => [S, A]): [S, A];
     decodeListNth<A>(s: S, i: number, k: (s: S) => [S, A]): [S, A];
   }

The ``List`` functions works like the record functions,
except they do not care about the name.

You have to tell the callback provided by ``DecoderImpl.decodeMaybe``
whether the value is null or not.

You have to tell the callback provided by ``DecoderImpl.decodeList``
the length of the list.


Client and Server
-----------------

All types in this section are located in module
``SOURCE_ROOT/gugugu/codec``.

.. sourcecode:: haskell

   module Hello where

   foo :: FooReq -> IO FooRes
   bar :: BarReq -> IO BarRes

becomes

.. sourcecode:: typescript

   export interface HelloServer<I, O> {
     foo(a: FooReq, meta: I): Promise<WithMeta<O, FooRes>>;
     bar(a: BarReq, meta: I): Promise<WithMeta<O, BarRes>>;
   }

   export interface HelloClient<I, O> {
     foo(a: FooReq, meta?: I): Promise<WithMeta<O, FooRes>>;
     bar(a: BarReq, meta?: I): Promise<WithMeta<O, BarRes>>;
   }

   class _HelloServer {
     public static toTransport<I, O, RA, RB, SA, SB>( impl: HelloServer<I, O>
                                                    , decoderImpl: DecoderImpl<SA, RA>
                                                    , encoderImpl: EncoderImpl<SB, RB>
                                                    ): ServerTransport<I, O, RA, RB>;
   }

   export const HelloServer = _HelloServer;

   class _HelloClient {
     public static fromTransport<I, O, RA, RB, SA, SB>( transport: ClientTransport<I, O, RA, RB>
                                                      , encoderImpl: EncoderImpl<SA, RA>
                                                      , decoderImpl: DecoderImpl<SB, RB>
                                                      ): HelloClient<I, O>;
   }

   export const HelloClient = _HelloClient;

The ``RA`` is the serialized type used by request,
and the ``RB`` is the serialized type used by response.
They are usually the same type but not necessary.

The ``I`` and ``O`` are metadata of request and response.


Server Usage
~~~~~~~~~~~~

.. sourcecode:: typescript

   export interface QualName {
     namespace: Array<string>;
     name: string;
   }

   export interface WithMeta<A, B> {
     meta: A;
     data: B;
   }

   export interface ServerTransport<I, O, RA, RB> {
     ask( name: QualName
        , codecHandler: ServerCodecHandler<I, O, RA, RB>
        ): null | ((fa: WithMeta<I, RA>) => Promise<WithMeta<undefined | O, RB>>);
   }

   export type ServerCodecHandler<I, O, RA, RB> =
     <A, B>( fa: WithMeta<I, RA>
           , decoder: (r: RA) => A
           , encoder: (b: B) => RB
           , k: (fa: WithMeta<I, A>) => Promise<WithMeta<undefined | O, B>>
           ) => Promise<WithMeta<undefined | O, RB>>;

``HelloServer.toTransport`` converts a ``HelloServer<I, O>`` into
a ``ServerTransport<I, O, RA, RB>``.
A ``ServerTransport<I, O, RA, RB>`` can handle request about type ``RA``
and return an response about type ``RB``.

To call the ``ServerTransport``,
you need a ``ServerCodecHandler<I, O, RA, RB>`` to handle the
encoding/decoding,
because Gugugu only knows how to decode from ``RA`` to ``A``
and encode from ``B`` to ``RB``,
but does not know how to handle possible exceptions.
The decoder and the encoder may throw exceptions if you do that in the
corresponding ``EncoderImpl``/``DecoderImpl``,
and you are responsible to handle that.

Please consult
:gugugu-source:`examples/lang/typescript/src/jsonhttp/server.ts`
for how to use the ``ServerTransport``.

Client Usage
~~~~~~~~~~~~

.. sourcecode:: typescript

   export interface QualName {
     namespace: Array<string>;
     name: string;
   }

   export interface WithMeta<A, B> {
     meta: A;
     data: B;
   }

   export interface ClientTransport<I, O, RA, RB> {
     send<A, B>( name: QualName
               , fa: WithMeta<undefined | I, A>
               , encoder: (a: A) => RA
               , decoder: (r: RB) => B
               ): Promise<WithMeta<O, B>>;
   }

``HelloClient.fromTransport`` converts a ``ClientTransport<I, O, RA, RB>``
into a ``HelloClient[F, G, M]``.
Like ``ServerTransport``, it can handle request about type ``RA``
and return an response about type ``RB``.
Like ``ServerCodecHandler``, you are responsible to handle possible exceptions.

Please consult
:gugugu-source:`examples/lang/typescript/src/jsonhttp/client.ts`
for how to write a ``ClientTransport``.

Command Line Options
--------------------

.. sourcecode:: none

   Usage: gugugu-typescript (-i|--input INPUT) (-o|--output OUTPUT)
                            (-p|--package-prefix PACKAGE_PREFIX) [--with-codec]
                            [--with-server] [--with-client]
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
                              the package prefix, e.g. path/to/generated
     --with-codec             pass this flag to generate codecs, default to false
     --with-server            pass this flag to generate server, default to false,
                              implies with-codec
     --with-client            pass this flag to generate client, default to false,
                              implies with-codec
     --trans-module-code ARG  module name transformer for code (default: lower)
     --trans-module-value ARG module name transformer for value (default: snake)
     --trans-module-type ARG  module name transformer for type of
                              client/server (default: id)
     --trans-func-code ARG    function name transformer for code (default: id)
     --trans-func-value ARG   function name transformer for value (default: snake)
     --trans-type-code ARG    type name transformer for code (default: id)
     --trans-type-func ARG    type name transformer in function (default: id)
     --trans-field-code ARG   record field name transformer for code (default: id)
     --trans-field-value ARG  record field name transformer for
                              value (default: snake)
     --trans-enum-code ARG    enum name transformer for code (default: id)
     --trans-enum-value ARG   enum name transformer for
                              value (default: upper-snake)
     -h,--help                Show this help text
     --help-transformers      list available name transformers
     --version                show version
