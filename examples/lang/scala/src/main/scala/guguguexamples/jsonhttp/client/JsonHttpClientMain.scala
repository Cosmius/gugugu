package guguguexamples.jsonhttp.client

import cats.effect.unsafe.IORuntime
import cats.effect.{IO, Resource}
import cats.implicits._
import guguguexamples.codec.JsonCodecImpl
import guguguexamples.definitions.hello._
import guguguexamples.definitions.hellotypes._
import guguguexamples.jsonhttp._
import guguguexamples.utils.EnvConfig
import org.http4s._
import org.http4s.blaze.client.BlazeClientBuilder
import org.http4s.client.Client
import org.typelevel.log4cats.Logger
import org.typelevel.log4cats.slf4j.Slf4jLogger

import java.time.LocalDateTime

object JsonHttpClientMain {

  def main(args: Array[String]): Unit = {
    implicit val ioRuntime: IORuntime = IORuntime.builder().build()
    run.unsafeRunSync()
  }

  def run: IO[Unit] = {
    helloModuleResource.use { hello =>
      for {
        _ <- doRequest {
          FoldRequest(values = Vector(1, 3, 4), initial = 2, op = Operation.Add)
        }(hello.fold)
        _ <- doRequest(10)(hello.calculateFibs)
        now <- IO.delay {
          LocalDateTime.now()
        }
        _ <- doRequest(now)(hello.incrOneDay)
      } yield ()
    }
  }

  private def doRequest[A, B](a: A)(k: WithMeta[A] => IO[WithMeta[B]]): IO[Unit] = {
    val reqWithMeta = (Map("X-Some-Meta" -> "2333"), a)
    for {
      resWithMeta <- k(reqWithMeta)
      (resMeta, res) = resWithMeta
      _ <- resMeta.toList.traverse_ { case (k, v) =>
        logger.info(s"Metadata: $k = $v")
      }
      _ <- logger.info(s"Got response: $res")
    } yield ()
  }

  private val logger: Logger[IO] = Slf4jLogger.getLogger

  def helloModuleResource: Resource[IO, HelloModule[WithMeta, WithMeta, IO]] = {
    httpClientResource.map { http =>
      val uriPrefix = Uri(
        scheme = Some(Uri.Scheme.http),
        authority = Some(Uri.Authority(
          host = Uri.RegName(EnvConfig.host),
          port = Some(EnvConfig.port),
        ))
      )
      val t = HttpClientTransport(http, uriPrefix)
      HelloModule.fromTransport(t, JsonCodecImpl, JsonCodecImpl)
    }
  }

  def httpClientResource: Resource[IO, Client[IO]] = {
    BlazeClientBuilder[IO].resource
  }

}
