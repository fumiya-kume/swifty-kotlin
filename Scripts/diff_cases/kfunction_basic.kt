// SKIP-DIFF
// STDLIB-REFLECT-063: KFunction complete implementation
import kotlin.reflect.KFunction

fun greet(name: String): String = "Hello, $name!"

fun add(a: Int, b: Int): Int = a + b

fun noArgs(): String = "no arguments"

suspend fun asyncWork(): Int = 42

fun main() {
    // KFunction reference via :: operator
    val greetRef: KFunction<String> = ::greet
    val addRef: KFunction<Int> = ::add
    val noArgsRef: KFunction<String> = ::noArgs

    // name property
    println("greetRef.name = ${greetRef.name}")
    println("addRef.name = ${addRef.name}")
    println("noArgsRef.name = ${noArgsRef.name}")

    // parameters (valueParameters) count via arity
    println("greetRef parameters count = ${greetRef.parameters.size}")
    println("addRef parameters count = ${addRef.parameters.size}")
    println("noArgsRef parameters count = ${noArgsRef.parameters.size}")

    // isSuspend
    println("greetRef.isSuspend = ${greetRef.isSuspend}")
    println("addRef.isSuspend = ${addRef.isSuspend}")

    // returnType (string representation)
    println("addRef.returnType = ${addRef.returnType}")

    // call() invocation
    val result1 = greetRef.call("World")
    println("greetRef.call(\"World\") = $result1")

    val result2 = addRef.call(3, 4)
    println("addRef.call(3, 4) = $result2")

    val result3 = noArgsRef.call()
    println("noArgsRef.call() = $result3")
}
