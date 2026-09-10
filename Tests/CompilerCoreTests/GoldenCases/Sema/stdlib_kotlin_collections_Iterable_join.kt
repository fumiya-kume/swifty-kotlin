import kotlin.text.Appendable

fun joinFamily(
    values: Iterable<Int>,
    buffer: Appendable,
    separator: CharSequence
): String {
    val joinedBuffer: Appendable = values.joinTo(
        buffer = buffer,
        separator = separator,
        prefix = "[",
        postfix = "]",
        limit = 2,
        truncated = "!"
    )
    val transformedBuffer: Appendable = values.joinTo(
        buffer = StringBuilder(),
        separator = separator,
        prefix = "{",
        postfix = "}",
        limit = 2,
        truncated = "!"
    ) { "b$it" }
    val plain = values.joinToString(
        separator = separator,
        prefix = "[",
        postfix = "]",
        limit = 2,
        truncated = "!"
    )
    val transformed = values.joinToString(
        separator = separator,
        prefix = "<",
        postfix = ">",
        limit = 2,
        truncated = "!"
    ) { "v$it" }
    val namedTransform = values.joinToString(
        separator = separator,
        transform = { "n$it" }
    )
    return joinedBuffer.toString() + transformedBuffer.toString() + plain + transformed + namedTransform
}
