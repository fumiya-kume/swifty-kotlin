fun describe(obj: Any): String = when (obj) {
    is Int -> "Int: ${obj + 1}"
    is String -> "String of length ${obj.length}"
    is Boolean -> if (obj) "true!" else "false!"
    is List<*> -> "List of size ${obj.size}"
    else -> "Unknown"
}
fun main() {
    println(describe(42))
    println(describe("hello"))
    println(describe(true))
    println(describe(listOf(1, 2, 3)))
    println(describe(3.14))
    val x: Any = "test"
    if (x is String) println(x.uppercase())
    val y: Any = 123
    val z = y as Int
    println(z + 1)
}
