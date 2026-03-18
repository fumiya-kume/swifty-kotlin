fun arrayOfInts() {
    val a = arrayOf(1, 2, 3)
    println(a.size)
}

fun arrayOfStrings() {
    val b = arrayOf("hello", "world")
    println(b.size)
}

fun intArrayOfLiteral() {
    val c = intArrayOf(10, 20, 30)
    println(c.size)
}

fun longArrayOfLiteral() {
    val d = longArrayOf(1L, 2L, 3L)
    println(d.size)
}

fun arrayConstructorWithInit() {
    val e = Array(5) { it * 2 }
    println(e.size)
}

fun arrayOfWithExpectedType() {
    val strings: Array<String> = arrayOf()
    println(strings.size)
}
