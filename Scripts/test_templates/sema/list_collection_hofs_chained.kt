fun chained(values: List<Int>) {
    val result = values.filter { it > 0 }
        .mapIndexed { i, v -> i + v }
        .flatMap { listOf(it, it * 2) }
        .associateWith { it.toString() }
    val groups = values.groupBy { it % 3 }.mapValues { it.value.size }
}
