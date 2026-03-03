package golden.sema

@Suppress("UNCHECKED_CAST")
fun suppressedCast(x: Any): String = x as String

fun unsuppressedCast(x: Any): String = x as String
