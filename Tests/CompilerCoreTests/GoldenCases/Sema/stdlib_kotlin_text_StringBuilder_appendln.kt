@file:Suppress("DEPRECATION_ERROR")

package golden.sema

fun appendlnValues(
    builder: StringBuilder,
    nullableAny: Any?,
    nullableString: String?
): StringBuilder {
    builder.appendln()
    builder.appendln(nullableAny)
    builder.appendln(true)
    builder.appendln((-2).toByte())
    builder.appendln(1.25)
    builder.appendln(2.5f)
    builder.appendln(3)
    builder.appendln(4L)
    builder.appendln(5.toShort())
    return builder.appendln(nullableString)
}
