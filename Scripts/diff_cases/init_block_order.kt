// CLASS-007: constructor init block and primary constructor property init order
// Verifies declaration-order (top-to-bottom) execution of property initializers
// and init blocks.

var counter = 0
fun nextId(): Int {
    counter = counter + 1
    return counter
}

class A {
    val x = nextId()
    init { println("init: x=$x") }
    val y = x + 1
    init { println("init: y=$y") }
}

fun main() {
    println("--- A ---")
    val a = A()
    println("a.x=${a.x} a.y=${a.y}")
}
