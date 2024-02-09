package guguguexamples.jsonhttp.client

import cats.effect.IO
import gugugu.lang.scala.runtime.transport._
import guguguexamples.jsonhttp._
import org.typelevel.log4cats.Logger
import org.typelevel.log4cats.slf4j.Slf4jLogger
import io.circe.Json
import org.http4s.circe._
import org.http4s.client.Client
import org.http4s._

case class HttpClientTransport(http: Client[IO], prefix: Uri)
  extends ClientTransport[WithMeta, WithMeta, IO, Json, Json] {

  private val logger: Logger[IO] = Slf4jLogger.getLogger

  override def send[A, B]( name: QualName[String]
                         , fa: WithMeta[A]
                         , encodeA: A => Json, decodeB: Json => B
                         ): IO[WithMeta[B]] = {
    val (reqMeta, a) = fa
    IO.delay(encodeA(a)).flatMap { r =>
      logger.info(s"Sending: $r") *>
      http.run {
        val hs = metaToHeaders(reqMeta)
        val uri = (name.namespace :+ name.name).foldLeft(prefix)(_ / _)
        Request[IO](Method.POST, uri)
          .withEntity(r)
          .putHeaders(hs.toSeq)
      }.use { res =>
        for {
          r <- res.as[Json]
          _ <- logger.info(s"Got data: $r")
          b <- IO.delay(decodeB(r))
        } yield {
          val resMeta = metaFromHeaders(res.headers)
          (resMeta, b)
        }
      }
    }
  }
}
