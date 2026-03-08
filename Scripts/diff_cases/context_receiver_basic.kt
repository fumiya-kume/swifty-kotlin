class Greeter {
    fun run() {
        println(message())
    }
}

context(Greeter)
fun message(): String = "hello"

fun main() {
    Greeter().run()
}
