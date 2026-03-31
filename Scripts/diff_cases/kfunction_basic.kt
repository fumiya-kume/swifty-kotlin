// SKIP-DIFF
// STDLIB-REFLECT-063: KFunction complete implementation
fun add(a: Int, b: Int): Int = a + b
fun greet(name: String): String = "Hello, $name!"

suspend fun asyncWork(): Int = 42

fun main() {
    val addRef = ::add
    // name
    println(addRef.name)            // add

    // isSuspend
    println(addRef.isSuspend)       // false

    // returnType (string representation)
    val returnType = addRef.returnType
    println(returnType)             // Int or kotlin.Int

    // parameters
    val params = addRef.parameters
    println(params.size)            // 2

    // call()
    val result = addRef.call(3, 4)
    println(result)                 // 7

    // greet function reference
    val greetRef = ::greet
    println(greetRef.name)          // greet
    val msg = greetRef.call("World")
    println(msg)                    // Hello, World!
}
