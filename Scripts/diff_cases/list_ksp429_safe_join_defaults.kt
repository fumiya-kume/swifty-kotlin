// Minimal regression for source-backed joinToString defaults through a safe call.
fun main() {
    val values: List<String>? = listOf("one", "two")
    println(values?.joinToString(","))
    println(values?.joinToString(prefix = "<", postfix = ">"))
    println(values?.joinToString(limit = 1))
    println(values?.joinToString(truncated = "more", limit = 1))
    val absent: List<String>? = null
    println(absent?.joinToString(limit = 1))
}
