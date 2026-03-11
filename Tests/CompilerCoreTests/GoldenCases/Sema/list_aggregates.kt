fun aggregate(values: List<Int>) {
    values.sumOf { it * 2 }
    values.maxOrNull()
    values.minOrNull()
}
