trait ServerCodecHandler[F[_], G[_], M[_], RA, RB] {
  def apply[A, B]( fr: F[RA]
                 , decodeA: RA => A
                 , encodeB: B => RB
                 , k: F[A] => M[G[B]]
                 ): M[G[RB]]
}
