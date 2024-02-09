use std::collections::HashMap;
use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;

use tokio::runtime::Runtime;
use serde_json::Value;
use hyper::client::HttpConnector;
use hyper::{Body, Client, Request};

use gugugu_rust_example::gugugu::lang::rust::runtime::codec::{
  EncoderImpl, Encoding, DecoderImpl, Decoding,
};
use gugugu_rust_example::gugugu::lang::rust::runtime::transport::{
  ClientTransport, GuguguClient
};

use gugugu_rust_example::definitions::hello::{FoldRequest, HelloModule};
use gugugu_rust_example::definitions::hellotypes::Operation;

use gugugu_rust_example::codec::json::JsonCodecImpl;
use gugugu_rust_example::jsonhttp::{
  Meta, MetaHandler, meta_from_headers,
  decode_json_from_body, encode_json_to_body,
};
use gugugu_rust_example::utils::{get_host_and_port, err};

fn main() -> ()
{
  let runtime = match Runtime::new() {
    Ok(v) => v,
    Err(_) => {
      println!("Cannot allocate tokio runtime");
      return ()
    },
  };

  if let Err(e) = runtime.block_on(async_main()) {
    println!("Error: {}", e);
  };
}

async fn async_main() -> Result<(), String>
{
  let client = {
    let transport = {
      let (host, port) = get_host_and_port();
      let prefix = format!("http://{}:{}/", host, port);
      let client = Client::new();
      let meta_handler = MetaHandler::new()?;
      SimpleHttpTransport {
        prefix: prefix,
        client: Arc::new(client),
        meta_handler: Arc::new(meta_handler),
      }
    };
    let codec_impl = Arc::new(JsonCodecImpl::new_default());
    GuguguClient {
      transport: transport,
      encoder_impl: codec_impl.clone(),
      decoder_impl: codec_impl,
    }
  };
  let (result, rmeta) = {
    let req = FoldRequest {
      initial: 2,
      op: Operation::Add,
      values: vec![1, 3, 4],
    };
    client.fold(req, HashMap::new())
  }.await?;
  println!("{:?} {:?}", result, rmeta);
  Ok(())
}

struct SimpleHttpTransport {
  prefix: String,
  client: Arc<Client<HttpConnector, Body>>,
  meta_handler: Arc<MetaHandler>,
}

impl ClientTransport<String, Meta, Meta, Value, Value, String, String>
  for SimpleHttpTransport
{
  fn send<A, B, CA, CB>
    ( &self
    , namespace: &[&str]
    , name: &str
    , a: A
    , i: Meta
    , ca: Arc<CA>
    , cb: Arc<CB>
    ) -> Pin<Box<dyn Future<Output = Result<(Meta, B), String>> + Send>>
  where A: Encoding + Send + 'static
      , B: Decoding + Send + 'static
      , CA: EncoderImpl<Error = String, Repr = Value> + Send + Sync + 'static
      , CB: DecoderImpl<Error = String, Repr = Value> + Send + Sync + 'static
  {
    let url = {
      let url_len = namespace
        .iter()
        .fold(
          self.prefix.len() + name.len() + namespace.len(),
          |z, p| z + p.len());
      let mut v = String::with_capacity(url_len);
      v.push_str(&self.prefix);
      for p in namespace {
        v.push_str(p);
        v.push('/');
      }
      v.push_str(name);
      v
    };
    let client = self.client.clone();
    let meta_handler = self.meta_handler.clone();
    Box::pin(async move {
      let req_json = match ca.encode_value(&a) {
        Ok(v) => v,
        Err(_) => return err("encoding error"),
      };
      let body = match encode_json_to_body(&req_json) {
        Ok(v) => v,
        Err(_) => return err("cannot encode body"),
      };
      let mut req = match Request::post(url).body(body) {
        Ok(v) => v,
        Err(_) => return err("impossible"),
      };
      match meta_handler.write_meta_to_headers(&i, req.headers_mut()) {
        Ok(()) => (),
        Err(_) => return err("cannot encode meta"),
      };
      let mut res = match client.request(req).await {
        Ok(v) => v,
        Err(_) => return err("network error"),
      };
      let res_meta = match meta_from_headers(res.headers()) {
        Ok(v) => v,
        Err(_) => return err("cannot decode meta"),
      };
      let j = match decode_json_from_body(res.body_mut()).await {
        Ok(v) => v,
        Err(_) => return err("cannot decode body"),
      };
      let b = match cb.decode_value(&j) {
        Ok(v) => v,
        Err(_) => return err("decoding error"),
      };
      Ok((res_meta, b))
    })
  }
}
