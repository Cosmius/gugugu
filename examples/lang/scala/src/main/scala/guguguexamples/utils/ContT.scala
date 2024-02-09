package guguguexamples.utils

import cats.{Monad, StackSafeMonad}

case class ContT[R, M[_], A](run: (A => M[R]) => M[R]) {

  def map[B](f: A => B): ContT[R, M, B] = {
    ContT(k => run(f.andThen(k)))
  }

  def flatMap[B](f: A => ContT[R, M, B]): ContT[R, M, B] = {
    ContT(k => run(a => f(a).run(k)))
  }

}

object ContT {

  def pure[R, M[_], A](a: A): ContT[R, M, A] = ContT(_(a))

  def lift[R, M[_], A](ma: M[A])(implicit M: Monad[M]): ContT[R, M, A] =
    ContT(M.flatMap(ma))

  def completeWith[R, M[_], A](mr: M[R]): ContT[R, M, A] = ContT(_ => mr)

  implicit def monadInstanceForContT[R, M[_]]: Monad[ContT[R, M, *]] = {
    new StackSafeMonad[ContT[R, M, *]] {
      override def pure[A](a: A): ContT[R, M, A] = ContT.pure(a)
      override def flatMap[A, B](fa: ContT[R, M, A])
                                (f: A => ContT[R, M, B]): ContT[R, M, B] = {
        fa.flatMap(f)
      }
    }
  }

}
