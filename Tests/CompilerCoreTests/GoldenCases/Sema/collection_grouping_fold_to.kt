fun testGroupingFoldTo(values: List<String>) {
    val dest = mutableMapOf<Int, Int>()
    val result = values.groupingBy { it.length }.foldTo(
        dest,
        initialValue = 0,
        operation = { accumulator, element ->
            accumulator + element.length
        }
    )
    println(result)
}

fun testGroupingFoldToWithSelector(values: List<String>) {
    val dest = mutableMapOf<Int, Int>()
    val result = values.groupingBy { it.length }.foldTo(
        dest,
        initialValueSelector = { key, element ->
            key + element.length
        },
        operation = { key, accumulator, element ->
            accumulator + key + element.length
        }
    )
    println(result)
}
