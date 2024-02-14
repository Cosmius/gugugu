import * as moment from "moment";
import {
  Moment
} from "moment";
import {
  EncoderImpl,
  DecoderImpl,
} from "../../gugugu-generated/gugugu/codec";


export type JsonRepr
  = null
  | boolean
  | number
  | string
  | JsonArray
  | JsonObject
  ;

export interface JsonObject {
  [k: string]: JsonRepr;
}

export interface JsonArray {
  [i: number]: JsonRepr;
  length: number;
}


export interface JsonCursor {
  top: JsonRepr;
  stack: Array<JsonRepr>;
}

class CodecError extends Error {}

const INT32_MAX: number = 2 ** 31 - 1;
const INT32_MIN: number = - (2 ** 31);


export class JsonCodecImpl implements EncoderImpl<JsonCursor, JsonRepr>
                                    , DecoderImpl<JsonCursor, JsonRepr> {
  public encodeWithState(k: (s: JsonCursor) => JsonCursor): JsonRepr {
    let s: JsonCursor = {
      top: null,
      stack: [],
    };
    s = k(s);
    if (s.stack.length > 0) {
      throw new CodecError("unexpected finalize");
    }
    return s.top;
  }

  public decodeWithState<A>( r: JsonRepr
                           , k: (s: JsonCursor) => [JsonCursor, A]
                           ): A {
    let s: JsonCursor = {
      top: r,
      stack: [],
    };
    let a: A;
    [s, a] = k(s);
    if (s.stack.length !== 0) {
      throw new CodecError("unexpected finalize");
    }
    return a;
  }


  public encodeUnit(s: JsonCursor, v: {}): JsonCursor {
    s.top = null;
    return s;
  }
  public decodeUnit(s: JsonCursor): [JsonCursor, {}] {
    if (s.top !== null) {
      throw new CodecError("cannot read Unit");
    }
    return [s, {}];
  }

  public encodeBool(s: JsonCursor, v: boolean): JsonCursor {
    s.top = v;
    return s;
  }
  public decodeBool(s: JsonCursor): [JsonCursor, boolean] {
    if (typeof s.top !== "boolean") {
      throw new CodecError("cannot read Bool");
    }
    return [s, s.top];
  }

  public encodeInt32(s: JsonCursor, v: number): JsonCursor {
    s.top = v;
    return s;
  }
  public decodeInt32(s: JsonCursor): [JsonCursor, number] {
    if ( typeof s.top !== "number"
      || !Number.isInteger(s.top)
      || s.top > INT32_MAX
      || s.top < INT32_MIN
       ) {
      throw new CodecError("cannot read Int32");
    }
    return [s, s.top];
  }

  public encodeDouble(s: JsonCursor, v: number): JsonCursor {
    s.top = v;
    return s;
  }
  public decodeDouble(s: JsonCursor): [JsonCursor, number] {
    if (typeof s.top !== "number") {
      throw new CodecError("cannot read Double");
    }
    return [s, s.top];
  }

  public encodeString(s: JsonCursor, v: string): JsonCursor {
    s.top = v;
    return s;
  }
  public decodeString(s: JsonCursor): [JsonCursor, string] {
    if (typeof s.top !== "string") {
      throw new CodecError("cannot read String");
    }
    return [s, s.top];
  }

  public encodeMaybe( s: JsonCursor, isNothing: boolean
                    , k: (s: JsonCursor) => JsonCursor): JsonCursor {
    if (isNothing) {
      s.top = null;
    }
    return k(s);
  }
  public decodeMaybe<A>( s: JsonCursor
                       , k: ( s: JsonCursor
                            , isNothing: boolean
                            ) => [JsonCursor, A]
                       ): [JsonCursor, A] {
    return k(s, s.top === null);
  }

  public encodeList( s: JsonCursor, len: number
                   , k: (s: JsonCursor) => JsonCursor): JsonCursor {
    s.top = [];
    return k(s);
  }
  public encodeListNth( s: JsonCursor, i: number
                      , k: (s: JsonCursor) => JsonCursor): JsonCursor {
    s.stack.push(s.top);
    s.top = null;
    s = k(s);
    if (s.stack.length === 0) {
      throw new CodecError("bad state: encodeListNth");
    }
    const oldTop = s.stack.pop();
    if (!Array.isArray(oldTop)) {
      throw new CodecError("bad state: encodeListNth");
    }
    oldTop.push(s.top);
    s.top = oldTop;
    return s;
  }
  public decodeList<A>( s: JsonCursor
                      , k: (s: JsonCursor, len: number) => [JsonCursor, A]
                      ): [JsonCursor, A] {
    if (!Array.isArray(s.top)) {
      throw new CodecError("cannot read List");
    }
    return k(s, s.top.length);
  }
  public decodeListNth<A>( s: JsonCursor, i: number
                         , k: (s: JsonCursor) => [JsonCursor, A]
                         ): [JsonCursor, A] {
    if (!Array.isArray(s.top)) {
      throw new CodecError("cannot read List");
    }
    if (i >= s.top.length) {
      throw new CodecError("bad state: decodeListNth");
    }
    s.stack.push(s.top);
    s.top = s.top[i];
    let a: A;
    [s, a] = k(s);
    const oldTop = s.stack.pop();
    if (oldTop === undefined) {
      throw new CodecError("bad state: decodeListNth");
    }
    s.top = oldTop;
    return [s, a];
  }

  public encodeRecord( s: JsonCursor, nFields: number
                     , k: (s: JsonCursor) => JsonCursor): JsonCursor {
    s.top = {};
    return k(s);
  }
  public encodeRecordField( s: JsonCursor, i: number
                          , name: string
                          , k: (s: JsonCursor) => JsonCursor): JsonCursor {
    s.stack.push(s.top);
    s.top = null;
    s = k(s);
    if (s.stack.length === 0) {
      throw new CodecError("bad state: encodeRecordField");
    }
    const oldTop = s.stack.pop();
    if (typeof oldTop !== "object" || oldTop === null) {
      throw new CodecError("bad state: encodeRecordField");
    }
    (oldTop as JsonObject)[name] = s.top;
    s.top = oldTop;
    return s;
  }
  public decodeRecord<A>( s: JsonCursor, nFields: number
                        , k: (s: JsonCursor) => [JsonCursor, A]
                        ): [JsonCursor, A] {
    if (typeof s.top !== "object" || s.top === null
        || Object.keys(s.top).length < nFields) {
      throw new CodecError("cannot read Record");
    }
    return k(s);
  }
  public decodeRecordField<A>( s: JsonCursor, i: number
                             , name: string
                             , k: (s: JsonCursor) => [JsonCursor, A]
                             ): [JsonCursor, A] {
    if (typeof s.top !== "object" || s.top === null) {
      throw new CodecError("cannot read Record");
    }
    const fieldObj = (s.top as JsonObject)[name];
    if (fieldObj === undefined) {
      throw new CodecError(`cannot read Record field: ${name}`);
    }
    s.stack.push(s.top);
    s.top = fieldObj;
    let a: A;
    [s, a] = k(s);
    const oldTop = s.stack.pop();
    if (oldTop === undefined) {
      throw new CodecError("bad state: decodeRecordField");
    }
    s.top = oldTop;
    return [s, a];
  }

  public encodeEnum<A>( s: JsonCursor, a: A
                      , asIndex: (a: A) => number
                      , asName: (a: A) => string
                      ): JsonCursor {
    return this.encodeString(s, asName(a));
  }
  public decodeEnum<A>( s: JsonCursor
                      , byIndex: (i: number) => null | A
                      , byName: (n: string) => null | A
                      ): [JsonCursor, A] {
    const [s1, name] = this.decodeString(s);
    const a = byName(name);
    if (a === null) {
      throw new CodecError("cannot read Enum");
    }
    return [s1, a];
  }

  private readonly format = "YYYY-MM-DDTHH:mm:ss";

  public encodeDateTime(s: JsonCursor, a: Moment): JsonCursor {
    return this.encodeString(s, a.format(this.format));
  }
  public decodeDateTime(s: JsonCursor): [JsonCursor, Moment] {
    const [s2, dateTimeS] = this.decodeString(s);
    const dateTime = moment(dateTimeS, this.format, true);
    return [s2, dateTime];
  }

}
