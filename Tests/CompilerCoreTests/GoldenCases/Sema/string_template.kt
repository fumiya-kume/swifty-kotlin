package golden.sema

fun main() {
    val name = "world"
    val x = 42
    val greeting = "Hello $name"
    val result = "value=${x}"
    println(greeting)
    println(result)
}
