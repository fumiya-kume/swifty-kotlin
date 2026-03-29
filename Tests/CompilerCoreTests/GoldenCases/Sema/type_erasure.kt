package golden.sema

// Star-projection 'is List<*>' is valid at runtime — no type-erasure warning.
fun isRawList(v: Any): Boolean = v is List<*>

// Star-projection 'as List<*>' is valid — no unchecked-cast warning.
fun asRawList(v: Any): List<*>? = v as? List<*>

fun printSizeIfList(v: Any) {
    if (v is List<*>) {
        println(v.size)
    }
}
