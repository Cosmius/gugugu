trait ClientTransport[F[_], G[_], M[_], RA, RB] {
  def send[A, B]( name: QualName[String]
                , fa: F[A]
                , encodeA: A => RA
                , decodeB: RB => B
                ): M[G[B]]
}
