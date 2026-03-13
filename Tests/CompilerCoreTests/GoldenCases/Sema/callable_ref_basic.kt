package golden.sema

fun greet(name: String): String = "Hello, $name"

fun main() {
    val ref = ::greet
    println(ref("World"))
}
