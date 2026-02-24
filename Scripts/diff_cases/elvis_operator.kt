fun main() {
  val a: String? = null
  val b: String? = "hello"
  println(a ?: "default")
  println(b ?: "default")
  val x: Int? = null
  val y: Int? = 42
  println(x ?: 0)
  println(y ?: 0)
}
