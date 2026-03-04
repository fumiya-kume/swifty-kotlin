package golden.diagnostics

@Suppress("UNCHECKED_CAST")
fun suppressed(v: Any): List<String> = v as List<String>

fun unsuppressed(v: Any): List<String> = v as List<String>
