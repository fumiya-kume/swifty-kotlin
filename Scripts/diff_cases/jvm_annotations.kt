// STDLIB-JVM-165: JVM-specific annotations and wrappers.
// Verifies that member-level JVM annotations are accepted and
// that default-argument Java overload entrypoints can be synthesized.

class Greeter {
    companion object {
        @JvmField
        var counter: Int = 0

        @JvmStatic
        fun bump() {
            counter++
        }
    }

    @JvmName("helloForJava")
    @JvmOverloads
    fun greet(prefix: String = "Hello", suffix: String = "!"): String {
        return prefix + suffix
    }
}

fun main() {
    Greeter.bump()
    println("counter=${Greeter.counter}")

    val greeter = Greeter()
    println(greeter.greet())
    println(greeter.greet("Hi"))
    println(greeter.greet("Welcome", "!!!"))
}
