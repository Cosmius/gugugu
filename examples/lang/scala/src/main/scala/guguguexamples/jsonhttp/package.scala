package guguguexamples

import org.http4s.{Header, Headers}
import org.typelevel.ci.CIString

package object jsonhttp {

  type WithMeta[A] = (Map[String, String], A)

  def metaFromHeaders(headers: Headers): Map[String, String] = {
    headers.headers.foldLeft(Map.empty[String, String]) { (map, h) =>
      map + ((h.name.toString, h.value))
    }
  }

  def metaToHeaders(metadata: Map[String, String]): Vector[Header.Raw] = {
    metadata.map { case (k, v) =>
      Header.Raw(CIString(k), v)
    }.toVector
  }

}
