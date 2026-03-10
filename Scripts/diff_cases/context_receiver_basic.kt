class Greeter {
    fun run() {
        println(message())
    }
}

context(_: Greeter)
fun message(): String = "hello"

fun main() {
    Greeter().run()
}
