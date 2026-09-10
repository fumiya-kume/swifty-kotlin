// RF-FIXTURE-020 / KSP-953: ifEmpty on Collection / Map / Array receivers —
// the fallback lambda may have a different type than the receiver, so the
// result is the join of C and R (annotated Any? to pin the inferred type).
// Identity (===) checks, lazy-evaluation call counts, and empty-input runs
// are executed by Scripts/diff_cases/stdlib_kotlin_collections_n_if.kt.
fun collectionIfEmpty(value: Collection<String?>) {
    val result: Any? = value.ifEmpty { "fallback" }
    val checked: Any? = result
}

fun mapIfEmpty(value: Map<String?, Int?>) {
    val result: Any? = value.ifEmpty { "fallback" }
    val checked: Any? = result
}

fun arrayIfEmpty(value: Array<String?>) {
    val result: Any? = value.ifEmpty { "fallback" }
    val checked: Any? = result
}
