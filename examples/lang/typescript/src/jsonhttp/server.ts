import * as http from "http";
import {
  IncomingMessage,
  ServerResponse,
} from "http";
import {
  Moment,
} from "moment";
import {
  QualName,
  WithMeta,
} from "../../gugugu-generated/gugugu/transport";
import {
  FoldRequest,
  HelloServer,
  AssociatedList,
} from "../../gugugu-generated/guguguexamples/definitions/hello";
import {
  AssociatedListEntry,
} from "../../gugugu-generated/guguguexamples/definitions/hellotypes";
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
  const impl = new HelloServerImpl();
  const serverTransport = HelloServer.toTransport(impl, jsonCodecImpl, jsonCodecImpl);

  const asyncHandler = async (req: IncomingMessage, res: ServerResponse) => {
    console.log(`Got request ${req.url}`);
    console.log(req.headers)
    let url = req.url;
    if (url === undefined) {
      return;
    }
    if (url.startsWith("/")) {
      url = url.substr(1);
    }
    const ps = url.split("/");
    const psLen = ps.length;

    if (psLen < 2) {
      res.writeHead(404)
      return;
    }

    const qualName: QualName = {
      namespace: ps.slice(0, psLen - 1),
      name: ps[psLen - 1],
    }

    const handler = serverTransport.ask(qualName, async (fr, decoder, encoder, k) => {
      const a = decoder(fr.data);
      const gb = await k({
        data: a,
        meta: fr.meta,
      });
      const r = encoder(gb.data)
      const gr = {
        meta: gb.meta,
        data: r,
      };
      return gr;
    });

    if (handler === null) {
      res.writeHead(404)
      return;
    }

    const body = await readAllAsUtf8String(req);
    console.log("Got data: " + body);
    const json = JSON.parse(body);
    const reqMeta = headersToMeta(req.headers);
    const gr = await handler({
      meta: reqMeta,
      data: json,
    });

    let resMeta = gr.meta;
    if (resMeta === undefined) {
      resMeta = {};
    }
    const resContent = JSON.stringify(gr.data);
    console.log("Sending: " + resContent);
    const resHeaders = metaToHeaders(resMeta);
    res.writeHead(200, resHeaders);
    res.write(resContent);
  };

  const server = http.createServer((req: IncomingMessage, res: ServerResponse) => {
    asyncHandler(req, res).catch(reason => {
      console.error(`Error occurred when handling request ${req.url}:`);
      console.error(reason);
      res.write(500);
    }).finally(() => {
      res.end();
    });
  });

  server.listen(guguguExamplePort, guguguExampleHost);

  console.log(`Server running at http://${guguguExampleHost}:${guguguExamplePort}`);
  console.log(`Press Ctrl-D to shut down the server`);
  await new Promise(resolve => {
    process.stdin.on("data", _ => {});
    process.stdin.on("end", resolve);
  });
  console.log(`Shutting down the server`);
  server.close();

}


class HelloServerImpl implements HelloServer<Metadata, Metadata> {

  public fold(a: FoldRequest, meta: Metadata): Promise<WithMeta<Metadata, number>> {
    return this.withMeta(a, meta, async req => {
      switch (req.op) {
        case "Add":
          return req.values.reduce((b, c) => b + c, req.initial);
        case "Mul":
          return req.values.reduce((b, c) => b * c, req.initial);
      }
    });
  }

  public calculateFibs(a: number, meta: Metadata): Promise<WithMeta<Metadata, AssociatedList>> {
    return this.withMeta(a, meta, async n => {
      const rv: Array<AssociatedListEntry> = [];
      let a = 0;
      let b = 1;
      for (let i = 0; i < n; i++) {
        const next = a + b;
        rv.push({
          index: i,
          value: b,
        });
        a = b;
        b = next;
      }
      return {
        entries: rv,
      };
    });
  }

  public incrOneDay(a: Moment, meta: Metadata): Promise<WithMeta<Metadata, Moment>> {
    return this.withMeta(a, meta, async t => {
      return t.clone().add(1, "days");
    });
  }

  private async withMeta<a, b>(a: a, meta: Metadata, k: (a: a) => Promise<b>): Promise<WithMeta<Metadata, b>> {
    const begin = (new Date()).getTime();
    Object.entries(meta).forEach(([k, v]) => {
      console.log(`Metadata: ${k} = ${v}`);
    });
    const b = await k(a);
    const end   = (new Date()).getTime();
    return {
      meta: {
        "X-Process-Time": `${begin - end}ms`,
      },
      data: b,
    };
  }

}


main().catch(reason => {
  console.error("Failed!");
  console.error(reason);
  process.exit(1);
});
