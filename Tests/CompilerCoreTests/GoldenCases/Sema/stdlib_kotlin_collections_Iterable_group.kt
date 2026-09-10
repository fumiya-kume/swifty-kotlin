fun groupFamily(
    values: Iterable<Int>,
    nullable: Iterable<String?>,
    destination: MutableMap<Any, MutableList<Int>>,
    list: List<Int>
) {
    val grouped: Map<Int, List<Int>> = values.groupBy { it % 2 }
    val transformed: Map<Int, List<String>> = values.groupBy(
        { it % 2 },
        { "n=$it" }
    )
    val nullableGroups: Map<String, List<String?>> = nullable.groupBy { it ?: "null" }
    val groupedTo: MutableMap<Any, MutableList<Int>> = values.groupByTo(destination) { it % 2 }
    val transformedTo: MutableMap<Any, MutableList<Int>> = values.groupByTo(
        destination,
        { it % 2 },
        { it * 10 }
    )
    val listGrouped: Map<Int, List<Int>> = list.groupBy { it % 2 }
}
