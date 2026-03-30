// STDLIB-METAPROG-116: Basic Metaprogramming — annotation stubs
// Verifies that @JvmStatic, @JvmField, @JvmOverloads, and @Suppress are
// accepted by the compiler without errors and produce correct output.

@Suppress("UNUSED_VARIABLE")
fun suppressExample() {
    val unused = 42
    println("suppress_ok")
}

class Counter {
    companion object {
        @JvmField
        var count: Int = 0

        @JvmStatic
        fun increment() {
            count++
        }

        @JvmStatic
        fun reset() {
            count = 0
        }
    }
}

class Greeter(val name: String) {
    @JvmOverloads
    fun greet(prefix: String = "Hello") {
        println("$prefix, $name!")
    }
}

fun main() {
    suppressExample()

    Counter.increment()
    Counter.increment()
    Counter.increment()
    println("count: ${Counter.count}")

    Counter.reset()
    println("after_reset: ${Counter.count}")

    val g = Greeter("World")
    g.greet()
    g.greet("Hi")
}
