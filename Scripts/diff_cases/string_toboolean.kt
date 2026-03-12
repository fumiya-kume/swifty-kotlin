fun main() {
    println("true".toBoolean())
    println("false".toBoolean())
    println("True".toBoolean())
    println("yes".toBoolean())
    println("".toBoolean())
    println("true".toBooleanStrict())
    println("false".toBooleanStrict())
    try {
        "yes".toBooleanStrict()
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }
}
