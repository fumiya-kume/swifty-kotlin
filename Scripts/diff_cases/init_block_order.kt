// CLASS-007: constructor init block and primary constructor property init order
// Verifies declaration-order (top-to-bottom) execution of property initializers
// and init blocks, plus secondary constructor delegation.

var counter = 0
fun nextId(): Int = ++counter

class MyClass {
    val a = run { println("init a"); 1 }
    init { println("init block 1") }
    val b = run { println("init b"); 2 }
    init { println("init block 2") }
}

// Completion condition:
// class A { val x = f(); init { println(x) }; val y = x + 1 }
// must initialise in declaration order.
class A {
    val x = nextId()
    init { println("init: x=$x") }
    val y = x + 1
    init { println("init: y=$y") }
}

// Secondary constructor must delegate to primary via this(...)
class WithSecondary(val name: String) {
    val tag: String
    init {
        tag = "[$name]"
        println("primary init: tag=$tag")
    }
    constructor(id: Int) : this("id=$id") {
        println("secondary body: tag=$tag")
    }
}

fun main() {
    println("--- MyClass ---")
    MyClass()
    println("--- A ---")
    val a = A()
    println("a.x=${a.x} a.y=${a.y}")
    println("--- WithSecondary(primary) ---")
    WithSecondary("hello")
    println("--- WithSecondary(secondary) ---")
    WithSecondary(42)
}
