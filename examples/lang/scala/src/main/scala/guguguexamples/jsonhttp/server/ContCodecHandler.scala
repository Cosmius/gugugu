package guguguexamples.jsonhttp.server

import cats.effect.IO
import gugugu.lang.scala.runtime.transport._
import guguguexamples.jsonhttp._
import guguguexamples.utils.ContT
import org.typelevel.log4cats.Logger
import org.typelevel.log4cats.slf4j.Slf4jLogger
import io.circe.Json
import org.http4s._

object ContCodecHandler extends
  ServerCodecHandler[WithMeta, WithMeta, HandlerF, Json, Json] {

  private val logger: Logger[IO] = Slf4jLogger.getLogger

  override def apply[A, B]( fr: WithMeta[Json]
                          , decodeA: Json => A
                          , encodeB: B => Json
                          , k: WithMeta[A] => HandlerF[WithMeta[B]]
                          ): HandlerF[WithMeta[Json]] = {
    val (reqMeta, reqR) = fr
    for {
      req <- ContT.lift {
        for {
          _ <- logger.info(s"Got data: $reqR")
          ea <- IO.delay {
            decodeA(reqR)
          }.attempt
        } yield ea
      }.flatMap {
        case Right(v) => ContT.pure[Response[IO], IO, A](v)
        case Left(_) => ContT.completeWith[Response[IO], IO, A] {
          IO.pure(Response[IO](Status.BadRequest))
        }
      }
      gb <- k((reqMeta, req))
      (resMeta, b) = gb
      resR <- ContT.lift {
        for {
          r <- IO.delay {
            encodeB(b)
          }
          _ <- logger.info(s"Sending: $r")
        } yield r
      }
    } yield (resMeta, resR)
  }
}
