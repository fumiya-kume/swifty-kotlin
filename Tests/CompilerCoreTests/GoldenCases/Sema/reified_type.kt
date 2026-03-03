package golden.sema

inline fun <reified T> typeNameOf(): String = T::class.simpleName ?: "unknown"

fun useReified(): String = typeNameOf<Int>()
