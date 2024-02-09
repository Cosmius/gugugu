trait ServerTransport[F[_], G[_], M[_], RA, RB] {
  def ask( name: QualName[String]
         , codecHandler: ServerCodecHandler[F, G, M, RA, RB]
         ): Option[F[RA] => M[G[RB]]]
}
