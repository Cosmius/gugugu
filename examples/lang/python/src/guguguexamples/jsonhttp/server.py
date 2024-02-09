import json
import logging
import sys
import time
from datetime import datetime, timedelta
from functools import reduce, wraps
from threading import Thread
from typing import TypeVar, Callable, Any, Iterable

from werkzeug.exceptions import NotFound
from werkzeug.serving import run_simple
from werkzeug.wrappers import Request, Response

from gugugu.lang.python.runtime.transport import QualName
from guguguexamples.codec.json import JsonCodecImpl
from guguguexamples.config import HOST, PORT
from guguguexamples.jsonhttp import WithMeta
from guguguexamples.definitions.hello import (
    HelloModule,
    FoldRequest,
    AssociatedList,
)
from guguguexamples.definitions.hellotypes import (
    Operation,
    AssociatedListEntry,
)

A = TypeVar("A")
B = TypeVar("B")

logger = logging.getLogger(__name__)


def with_meta(f: Callable[[Any, A], B],
              ) -> Callable[[Any, WithMeta[A]], WithMeta[B]]:
    @wraps(f)
    def wrapper(self, fa: WithMeta[A]) -> WithMeta[B]:
        begin = time.time()
        for k, v in fa.meta.items():
            logger.info(f"Got metadata: {k} = {v}")
        b = f(self, fa.data)
        end = time.time()
        r_meta = {
            "X-Process-Time": f"{(end - begin) * 1000} ms",
        }
        return WithMeta(r_meta, b)
    return wrapper


class HelloModuleImpl(HelloModule):

    @with_meta
    def fold(self, req: FoldRequest) -> int:
        if req.op == Operation.ADD:
            return reduce(lambda z, x: z + x, req.values, req.initial)
        else:  # Operation.MUL
            return reduce(lambda z, x: z * x, req.values, req.initial)

    @with_meta
    def calculate_fibs(self, n: int) -> AssociatedList:
        a = 0
        b = 1
        rv = []
        for i in range(n):
            rv.append(AssociatedListEntry(i, b))
            a, b = b, a + b
        return AssociatedList(rv)

    @with_meta
    def incr_one_day(self, a: datetime) -> datetime:
        return a + timedelta(days=1)


class WsgiApp(Thread):

    def __init__(self):
        super().__init__()
        self.daemon = True
        codec_impl = JsonCodecImpl()
        impl = HelloModuleImpl()
        self.transport = HelloModule.to_transport(impl, codec_impl, codec_impl)

    def run(self) -> None:
        run_simple(HOST, PORT, self.wsgi_app)

    def wsgi_app(self, environ, start_response) -> Iterable[bytes]:
        request = Request(environ)
        parts = request.path.lstrip("/").split("/")
        qual_name = QualName(parts[:-1], parts[-1])
        handler = self.transport.ask(qual_name, self.handle_encoding)
        if handler is None:
            raise NotFound
        meta = dict()
        for k, v in request.headers.items():
            meta[k] = v
        data = json.load(request.stream)
        r_with_meta = handler(WithMeta(meta, data))
        serialized = json.dumps(
            r_with_meta.data,
            ensure_ascii=False,
        )
        r = Response(
            serialized, status=200, content_type="application/json")
        for k, v in r_with_meta.meta.items():
            r.headers[k] = v
        return r(environ, start_response)

    @staticmethod
    def handle_encoding(decoder, encoder, handler, fr):
        decoded = decoder(fr.data)
        fb = handler(WithMeta(fr.meta, decoded))
        encoded = encoder(fb.data)
        return WithMeta(fb.meta, encoded)


def main():
    logging.basicConfig(
        level=logging.INFO,
    )
    t = WsgiApp()
    t.start()
    print("Press Ctrl-D to shut down the server")
    sys.stdin.read()
    print("Shutting down the server")


if __name__ == "__main__":
    main()
