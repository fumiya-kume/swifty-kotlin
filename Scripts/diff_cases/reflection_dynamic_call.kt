fun add(a: Int, b: Int): Int = a + b
fun greet(name: String): String = "Hello, $name!"
fun sum3(a: Int, b: Int, c: Int): Int = a + b + c
fun main() {
    val addRef = ::add
    println(addRef(3, 4))
    val greetRef = ::greet
    println(greetRef("World"))
    val sum3Ref = ::sum3
    println(sum3Ref(1, 2, 3))
    println((::add)(5, 6))
}
