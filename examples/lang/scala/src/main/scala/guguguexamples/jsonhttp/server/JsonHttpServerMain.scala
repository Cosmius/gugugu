package guguguexamples.jsonhttp.server

import cats.data.{Kleisli, NonEmptyVector}
import cats.effect.unsafe.IORuntime
import cats.effect.{IO, Resource}
import gugugu.lang.scala.runtime.transport._
import guguguexamples.codec.JsonCodecImpl
import guguguexamples.definitions.hello._
import guguguexamples.jsonhttp._
import guguguexamples.jsonhttp.server.impl._
import guguguexamples.utils._
import io.circe.Json
import org.http4s._
import org.http4s.circe._
import org.http4s.server.Server
import org.http4s.blaze.server.BlazeServerBuilder
import org.typelevel.log4cats.Logger
import org.typelevel.log4cats.slf4j.Slf4jLogger

import java.net.InetSocketAddress

object JsonHttpServerMain {

  def main(args: Array[String]): Unit = {
    implicit val ioRuntime: IORuntime = IORuntime.builder().build()
    run.unsafeRunSync()
  }

  def run: IO[Unit] = {
    serverResource.use { _ =>
      IO.delay {
        println("Press Ctrl-D to shut down the server")
        while (System.in.read() >= 0) {}
        println("Shutting down the server")
      }
    }
  }

  private val logger: Logger[IO] = Slf4jLogger.getLogger

  def serverResource: Resource[IO, Server] = {
    val addr = InetSocketAddress.createUnresolved(
      EnvConfig.host, EnvConfig.port)
    BlazeServerBuilder[IO]
      .bindSocketAddress(addr)
      .withHttpApp {
        Kleisli { req =>
          for {
            _ <- logger.info(s"Got request: $req")
            r <- handleRequest(req).run(IO.pure)
          } yield r
        }
      }
      .resource
  }

  lazy val transport: ServerTransport[WithMeta, WithMeta, HandlerF, Json, Json] = {
    HelloModule.toTransport(new HelloImpl, JsonCodecImpl, JsonCodecImpl)
  }

  def handleRequest(req: Request[IO]): HandlerF[Response[IO]] = {
    (for {
      ps <- NonEmptyVector.fromVector {
        req.pathInfo.toString().stripPrefix("/").split('/').toVector
      }
      qualName = QualName(ps.init, ps.last)
      k <- transport.ask(qualName, ContCodecHandler)
    } yield {
      val reqMeta = metaFromHeaders(req.headers)
      for {
        reqR <- ContT.lift {
          req.as[Json].attempt
        }.flatMap {
          case Right(v) => ContT.pure[Response[IO], IO, Json](v)
          case Left(e) => ContT.completeWith[Response[IO], IO, Json] {
            IO.pure {
              Response[IO](Status.BadRequest)
            }
          }
        }
        resWithMeta <- k((reqMeta, reqR))
      } yield {
        val (resMeta, resR) = resWithMeta
        val hs = metaToHeaders(resMeta)
        Response[IO]()
          .withEntity(resR)
          .putHeaders(hs.toSeq)
      }
    }).getOrElse(ContT.pure(Response[IO](Status.NotFound)))

  }

}
