fun main() {
    val x: Any = "hello"
    val result = when (x) {
        is String if x.length > 3 -> "long string"
        is String -> "short string"
        is Int if x > 0 -> "positive"
        is Int -> "non-positive"
        else -> "other"
    }
    println(result)
}
