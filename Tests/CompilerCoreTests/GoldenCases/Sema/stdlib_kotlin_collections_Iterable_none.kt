fun probe(values: Iterable<Int>, nullable: Iterable<String?>, list: List<Int>) {
    val iterableNone = values.none()
    val iterableNonePredicate = values.none { it > 1 }
    val nullableNone = nullable.none { it == null }
    val listNone = list.none()
    val listNonePredicate = list.none { it > 1 }
}
