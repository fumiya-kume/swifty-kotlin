// STDLIB-REFLECT-063: KFunction complete implementation
import kotlin.reflect.KFunction

fun greet(name: String): String = "Hello, $name!"

fun add(a: Int, b: Int): Int = a + b

fun main() {
    // KFunction reference via :: operator
    val greetRef: KFunction<String> = ::greet
    val addRef: KFunction<Int> = ::add

    // isSuspend
    println("greetRef.isSuspend = ${greetRef.isSuspend}")
    println("addRef.isSuspend = ${addRef.isSuspend}")
}
