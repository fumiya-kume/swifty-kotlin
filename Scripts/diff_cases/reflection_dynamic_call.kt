// STDLIB-REFLECT-067: reflection dynamic call — KFunction.call(), KProperty.get/set(), KConstructor.call()
fun add(a: Int, b: Int): Int = a + b
fun greet(name: String): String = "Hello, $name!"
fun sum3(a: Int, b: Int, c: Int): Int = a + b + c
fun main() {
    val addRef = ::add
    val result = addRef.call(3, 4)
    println(result)          // 7
    val greetRef = ::greet
    val msg = greetRef.call("World")
    println(msg)             // Hello, World!
    val sum3Ref = ::sum3
    val total = sum3Ref.call(1, 2, 3)
    println(total)           // 6
    println(addRef.name)     // add
    println(greetRef.name)   // greet
}
