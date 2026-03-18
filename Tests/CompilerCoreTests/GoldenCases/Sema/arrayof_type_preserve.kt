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

fun doubleArrayOfLiteral() {
    val e = doubleArrayOf(1.5, 2.5, 3.5)
    println(e.size)
}

fun floatArrayOfLiteral() {
    val f = floatArrayOf(1.5f, 2.5f, 3.5f)
    println(f.size)
}

fun booleanArrayOfLiteral() {
    val g = booleanArrayOf(true, false, true)
    println(g.size)
}

fun charArrayOfLiteral() {
    val h = charArrayOf('a', 'b', 'c')
    println(h.size)
}

fun arrayOfMixed() {
    val mixed = arrayOf(1, "two", 3.0)
    println(mixed.size)
}

fun arrayConstructorWithInit() {
    val i = Array(5) { it * 2 }
    println(i.size)
}

fun arrayOfWithExpectedType() {
    val strings: Array<String> = arrayOf()
    println(strings.size)
}
