package guguguexamples.jsonhttp.server.impl

import java.time.LocalDateTime
import cats.effect.{IO, Clock}
import cats.implicits._
import guguguexamples.definitions.hello._
import guguguexamples.definitions.hellotypes._
import guguguexamples.jsonhttp.WithMeta
import guguguexamples.jsonhttp.server.HandlerF
import guguguexamples.utils.ContT
import org.typelevel.log4cats.Logger
import org.typelevel.log4cats.slf4j.Slf4jLogger

class HelloImpl(implicit clock: Clock[IO])
  extends HelloModule[WithMeta, WithMeta, HandlerF] {

  private val logger: Logger[IO] = Slf4jLogger.getLogger

  override def fold(fa: WithMeta[FoldRequest]): HandlerF[WithMeta[Int]] = {
    withMeta(fa) { req =>
      ContT.lift {
        IO.pure {
          req.op match {
            case Operation.Add => req.values.foldLeft(req.initial)(_ + _)
            case Operation.Mul => req.values.foldLeft(req.initial)(_ * _)
          }
        }
      }
    }
  }

  override def calculateFibs(fa: WithMeta[Int]): HandlerF[WithMeta[AssociatedList]] = {
    withMeta(fa) { n =>
      ContT.lift { IO.pure {
        val rv = Vector.newBuilder[AssociatedListEntry]
        var a = 0
        var b = 1
        (0 until n).foreach { i =>
          val next = a + b
          rv += AssociatedListEntry(index = i, value = b)
          a = b
          b = next
        }
        AssociatedList(rv.result())
      }}
    }
  }

  override def incrOneDay(fa: WithMeta[LocalDateTime]): HandlerF[WithMeta[LocalDateTime]] = {
    withMeta(fa) { d =>
      ContT.pure(d.plusDays(1))
    }
  }

  private def withMeta[A, B](fa: WithMeta[A])
                            (k: A => HandlerF[B]): HandlerF[WithMeta[B]] = {
    val (metadata, a) = fa
    for {
      begin <- ContT.lift(clock.realTime)
      _ <- metadata.toList.traverse_[HandlerF, Unit] { case (k, v) =>
        ContT.lift(logger.info(s"Got Metadata: $k = $v"))
      }
      b <- k(a)
      end <- ContT.lift(clock.realTime)
    } yield (Map("X-Process-Time" -> s"${(end - begin).toMillis}ms"), b)
  }

}
