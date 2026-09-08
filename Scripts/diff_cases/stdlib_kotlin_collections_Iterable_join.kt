import kotlin.text.Appendable

fun main() {
    val values: Iterable<Int> = listOf(1, 2, 3)
    val separator: CharSequence = StringBuilder("|")
    val buffer: Appendable = StringBuilder("seed:")

    println(values.joinTo(
        buffer = buffer,
        separator = separator,
        prefix = "[",
        postfix = "]",
        limit = 2,
        truncated = "!"
    ).toString())
    println(values.joinTo(
        buffer = StringBuilder(),
        separator = separator,
        prefix = "{",
        postfix = "}",
        limit = 2,
        truncated = "!"
    ) { "b$it" }.toString())
    println(values.joinToString(
        separator = separator,
        prefix = "[",
        postfix = "]",
        limit = 2,
        truncated = "!"
    ))
    println(values.joinToString(
        separator = separator,
        prefix = "<",
        postfix = ">",
        limit = 2,
        truncated = "!"
    ) { "v$it" })
    println(values.joinToString(separator = separator, transform = { "n$it" }))
    println(values.joinToString { it.toString() })
}
