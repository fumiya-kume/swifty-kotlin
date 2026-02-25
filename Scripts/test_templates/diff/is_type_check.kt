fun describe(v: Any): String = when {
    v is String -> "string($v)"
    v is Int -> "int($v)"
    v !is Boolean -> "other"
    else -> "bool"
}

fun main() {
    println(describe("hi"))
    println(describe(42))
    println(describe(true))
    println(describe(3.14))
}
