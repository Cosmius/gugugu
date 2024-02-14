import * as http from "http";
import * as moment from "moment";
import {
  QualName,
  WithMeta,
  ClientTransport,
} from "../../gugugu-generated/gugugu/transport";
import {
  HelloClient,
} from "../../gugugu-generated/guguguexamples/definitions/hello";
import {
  JsonCodecImpl,
  JsonRepr,
} from "../codec/json-codec";
import {
  guguguExampleHost,
  guguguExamplePort,
} from "../utils";
import {
  Metadata,
  readAllAsUtf8String,
  headersToMeta,
  metaToHeaders,
} from "./common";


async function main(): Promise<void> {
  const jsonCodecImpl = new JsonCodecImpl();
  const urlPrefix = `http://${guguguExampleHost}:${guguguExamplePort}`;
  const clientTransport = new HttpClientTransport(urlPrefix);

  const client = HelloClient.fromTransport(
    clientTransport, jsonCodecImpl, jsonCodecImpl);

  await doRequest({
    values: [1, 3, 4],
    initial: 2,
    op: "Add",
  }, client.fold);
  await doRequest(10, client.calculateFibs);
  const now = moment();
  await doRequest(now, client.incrOneDay);
}


class HttpClientTransport
    implements ClientTransport<Metadata, Metadata, JsonRepr, JsonRepr> {

  constructor(private prefix: string) { }

  public async send<A, B>( name: QualName
                         , fa: WithMeta<undefined | Metadata, A>
                         , encoder: (a: A) => JsonRepr
                         , decoder: (r: JsonRepr) => B
                         ): Promise<WithMeta<Metadata, B>> {
    let reqMeta = fa.meta;
    if (reqMeta === undefined) {
      reqMeta = {};
    }
    const path = this.prefix + "/" + name.namespace.join("/") + "/" + name.name;
    const payload = JSON.stringify(encoder(fa.data));
    const reqHeaders = metaToHeaders(reqMeta);

    const gs = await new Promise<WithMeta<Metadata, string>>((resolve) => {
      const req = http.request(path, {
        method: "POST",
        headers: reqHeaders,
      }, async res => {
        const resMeta = headersToMeta(res.headers);
        const body = await readAllAsUtf8String(res);
        console.log("Got data: " + body);
        resolve({
          meta: resMeta,
          data: body,
        });
      });
      console.log("Sending: " + payload);
      req.write(payload);
      req.end();
    });

    const b = decoder(JSON.parse(gs.data));
    return {
      meta: gs.meta,
      data: b,
    };
  }

}

type Func<A, B> = (a: A, meta?: Metadata) => Promise<WithMeta<Metadata, B>>;

async function doRequest<A, B>(a: A, k: Func<A, B>): Promise<void> {
  const r = await k(a, {
      "X-Some-Meta": "233",
  });
  console.log("Meta:");
  console.log(r.meta);
  console.log(r.data);
}


main().catch(reason => {
  console.error("Failed!");
  console.error(reason);
  process.exit(1);
});
