class MyClass {
    val a = run { println("init a"); 1 }
    init { println("init block 1") }
    val b = run { println("init b"); 2 }
    init { println("init block 2") }
}

fun main() {
    MyClass()
}
