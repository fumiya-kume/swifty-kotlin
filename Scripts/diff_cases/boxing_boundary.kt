fun printAny(x: Any?) {
  println(x)
}
fun main() {
  println(42)
  println(null)
  printAny(100)
  printAny(null)
}
