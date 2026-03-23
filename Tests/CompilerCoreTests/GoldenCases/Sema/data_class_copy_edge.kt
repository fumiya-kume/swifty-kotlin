data class Point(val x: Int, val y: Int)

data class Name(val value: String)

fun testCopyBasic() {
    val p = Point(1, 2)
    val p2 = p.copy()
    println(p2.x)
    println(p2.y)
}

fun testCopyWithOverride() {
    val p = Point(1, 2)
    val p3 = p.copy(x = 10)
    println(p3.x)
}

fun testCopySingleProperty() {
    val n = Name("hello")
    val n2 = n.copy(value = "world")
    println(n2.value)
}
