// STDLIB-REFLECT-067: reflection dynamic call — KFunction.call(), KProperty.get/set(), KConstructor.call()
fun add(a: Int, b: Int): Int = a + b

fun greet(name: String): String = "Hello, $name!"

fun sum3(a: Int, b: Int, c: Int): Int = a + b + c

fun main() {
    // KFunction.call() via callable reference — arity 2
    val addRef = ::add
    val result = addRef.call(3, 4)
    println(result)          // 7

    // KFunction.call() — arity 1
    val greetRef = ::greet
    val msg = greetRef.call("World")
    println(msg)             // Hello, World!

    // KFunction.call() — arity 3
    val sum3Ref = ::sum3
    val total = sum3Ref.call(1, 2, 3)
    println(total)           // 6

    // KFunction.name
    println(addRef.name)     // add
    println(greetRef.name)   // greet
}
