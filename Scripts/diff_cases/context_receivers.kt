class Context(val prefix: String)

class Greeter {
    fun run() {
        println(message())
        println(secondary())
    }
}

context(Context)
fun message(): String = prefix + " hello"

context(Context)
fun secondary(): String = prefix.uppercase()

fun main() {
    with(Context("hi")) {
        Greeter().run()
    }
}
