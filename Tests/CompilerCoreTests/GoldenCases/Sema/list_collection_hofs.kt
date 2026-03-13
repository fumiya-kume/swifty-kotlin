fun transform(values: List<String>) {
    val indexed = values.mapIndexed { index, item -> "$index: $item" }
    val flat = values.flatMap { listOf(it, it.uppercase()) }
    val assoc = values.associate { it to it.length }
    val byKey = values.associateBy { it.first() }
    val withVal = values.associateWith { it.length }
    val grouped = values.groupBy { it.length }
    val (matching, rest) = values.partition { it.length > 3 }
}
