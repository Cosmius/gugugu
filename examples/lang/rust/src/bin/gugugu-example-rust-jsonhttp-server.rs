use std::collections::HashMap;
use std::convert::Infallible;
use std::future::Future;
use std::net::SocketAddr;
use std::pin::Pin;
use std::sync::Arc;

use tokio::io::AsyncReadExt;
use tokio::runtime::Runtime;
use serde_json::Value;
use http::StatusCode;
use hyper::service::{make_service_fn, service_fn};
use hyper::{Body, Request, Response, Server};
use chrono::{Duration, NaiveDateTime};

use gugugu_rust_example::gugugu::lang::rust::runtime::codec::{
  EncoderImpl, Encoding, DecoderImpl, Decoding,
};
use gugugu_rust_example::gugugu::lang::rust::runtime::transport::{
  ServerCodecHandler
};

use gugugu_rust_example::definitions::hello::{
  HelloModule, ask_transport, AssociatedList, FoldRequest,
};
use gugugu_rust_example::definitions::hellotypes::{
  AssociatedListEntry, Operation,
};

use gugugu_rust_example::codec::json::JsonCodecImpl;
use gugugu_rust_example::jsonhttp::{
  Meta, MetaHandler, meta_from_headers,
  decode_json_from_body, encode_json_to_body,
};
use gugugu_rust_example::utils::{get_host_and_port, err};

fn main() -> () {
  let runtime = match Runtime::new() {
    Ok(v) => v,
    Err(_) => {
      println!("Cannot allocate tokio runtime");
      return ()
    },
  };

  match runtime.block_on(async_main()) {
    Ok(_)  => (),
    Err(e) => println!("Error: {}", e),
  }
}

async fn async_main() -> Result<(), String> {
  let (host, port) = get_host_and_port();
  let ipaddr = match host.parse() {
    Ok(v) => v,
    Err(_) => return err("impossible"),
  };
  let addr = SocketAddr::new(ipaddr, port);
  let meta_handler = MetaHandler::new()?;
  let hello = Hello {
    meta_handler: meta_handler,
  };
  let srv = Arc::new(hello);
  let ch = SimpleCodecHandler;
  let ci = Arc::new(JsonCodecImpl::new_default());
  let make_svc = make_service_fn(move |_conn| {
    let srv1 = srv.clone();
    let ch1 = ch.clone();
    let ci1 = ci.clone();
    let handler = service_fn(move |req: Request<Body>| {
      handle_request(srv1.clone(), ch1.clone(), ci1.clone(), req)
    });
    async move {
      Ok::<_, Infallible>(handler)
    }
  });
  println!("Server is about to start");
  let server = Server::bind(&addr)
    .serve(make_svc)
    .with_graceful_shutdown(async {
      let mut stdin = tokio::io::stdin();
      let mut buf = Vec::with_capacity(1024);
      println!("Press Ctrl-D to shut down the server");
      loop {
        match stdin.read(&mut buf).await {
          Ok(0)  => break,
          Err(_) => break,
          _      => (),
        };
      };
      println!("Shutting down the server");
    });
  match server.await {
    Ok(_)  => Ok(()),
    Err(e) => Err(e.to_string()),
  }
}

async fn handle_request
  ( srv: Arc<Hello>
  , ch: SimpleCodecHandler
  , ci: Arc<JsonCodecImpl>
  , mut req: Request<Body>
  ) -> Result<Response<Body>, Infallible>
{
  let path = req.uri().path().to_string();
  let mut components: Vec<&str> = path.split('/').skip(1).collect();
  let last = match components.pop() {
    Some(v) => v,
    None => return respond(StatusCode::NOT_FOUND, "Not Found"),
  };
  let handler = match ask_transport(&components, last) {
    Some(v) => v,
    None => return respond(StatusCode::NOT_FOUND, "Not Found"),
  };
  let meta = match meta_from_headers(req.headers()) {
    Ok(v) => v,
    Err(_) => return respond(StatusCode::BAD_REQUEST, "Bad request"),
  };
  let j = match decode_json_from_body(req.body_mut()).await {
    Ok(v) => v,
    Err(_) => return respond(StatusCode::BAD_REQUEST, "Bad request"),
  };
  let (rmeta, rj) = match handler(srv.clone(), &ch, ci.clone(), ci, j, meta).await {
    Ok(v) => v,
    Err(_) => return respond(StatusCode::INTERNAL_SERVER_ERROR, "Internal server error"),
  };
  let body = match encode_json_to_body(&rj) {
    Ok(v) => v,
    Err(_) => return respond(StatusCode::INTERNAL_SERVER_ERROR, "Internal server error"),
  };
  let mut r = Response::new(body);
  match srv.meta_handler.write_meta_to_headers(&rmeta, r.headers_mut()) {
    Ok(()) => (),
    Err(_) => return respond(StatusCode::INTERNAL_SERVER_ERROR, "Internal server error"),
  };
  Ok(r)
}

fn respond<A>(status: StatusCode, body: &str) -> Result<Response<Body>, A>
{
  let res_body = Body::from(String::from(body));
  let mut r = Response::new(res_body);
  *r.status_mut() = status;
  Ok(r)
}

#[derive(Debug, Clone)]
struct SimpleCodecHandler;

type SimpleFuture<A> = Pin<Box<dyn Future<Output = Result<(Meta, A), String>> + Send>>;

impl ServerCodecHandler<String, Meta, Meta, Value, Value, String, String> for SimpleCodecHandler {
  type OutputFuture = SimpleFuture<Value>;
  fn run<A, CA, CB, B, R>
    ( &self
    , ca: Arc<CA>
    , cb: Arc<CB>
    , k: impl FnOnce(A, Meta) -> R + Send + 'static
    , ra: Value
    , i: Meta
    ) -> Self::OutputFuture
  where R: Future<Output = Result<(Meta, B), String>> + Send
      , A: Decoding + Send + 'static
      , B: Encoding + Send + 'static
      , CA: DecoderImpl<Error = String, Repr = Value> + Send + Sync + 'static
      , CB: EncoderImpl<Error = String, Repr = Value> + Send + Sync + 'static
  {
    Box::pin(async move {
      let a = ca.decode_value(&ra)?;
      let (o, b) = k(a, i).await?;
      let rb = cb.encode_value(&b)?;
      Ok((o, rb))
    })
  }
}

#[derive(Debug, Clone)]
pub struct Hello {
  meta_handler: MetaHandler,
}

impl HelloModule<String, Meta, Meta> for Hello {
  type FoldFuture = SimpleFuture<i32>;
  fn fold(&self, a: FoldRequest, i: Meta) -> Self::FoldFuture {
    Box::pin(async move {
      println!("{:?}", i);
      let rmeta = HashMap::new();
      let r = match a.op {
        Operation::Add => a.values.iter().fold(a.initial, |z, x| z + x),
        Operation::Mul => a.values.iter().fold(a.initial, |z, x| z * x),
      };
      Ok((rmeta, r))
    })
  }

  type CalculateFibsFuture = SimpleFuture<AssociatedList>;
  fn calculate_fibs(&self, n: i32, i: Meta) -> Self::CalculateFibsFuture {
    Box::pin(async move {
      println!("{:?}", i);
      let rmeta = HashMap::new();
      let mut v = Vec::with_capacity(n as usize);
      let mut a = 0;
      let mut b = 1;
      for i in 0..n {
        let c = a + b;
        a = b;
        b = c;
        let item = AssociatedListEntry{ index: i, value: a };
        v.push(item);
      }
      Ok((rmeta, AssociatedList{ entries: v }))
    })
  }

  type IncrOneDayFuture = SimpleFuture<NaiveDateTime>;
  fn incr_one_day(&self, dt: NaiveDateTime, i: Meta) -> Self::IncrOneDayFuture {
    Box::pin(async move {
      println!("{:?}", i);
      let rmeta = HashMap::new();
      Ok((rmeta, dt + Duration::days(1)))
    })
  }
}
