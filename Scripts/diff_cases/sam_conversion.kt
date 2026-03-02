fun interface Action {
    fun run(): String
}

fun execute(action: Action): String = action.run()

fun main() {
    val result = execute { "hello" }
    println(result)
}
