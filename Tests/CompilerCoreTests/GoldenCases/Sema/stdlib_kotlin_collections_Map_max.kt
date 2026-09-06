fun mapMaxFamilySurface(values: Map<out String, Int>) {
    val maxBy: Map.Entry<String, Int> = values.maxBy { it.value }
    val maxOfComparable: Int = values.maxOf { it.value }
    val maxOfDouble: Double = values.maxOf { it.value.toDouble() }
    val maxOfFloat: Float = values.maxOf { it.value.toFloat() }
    val maxOfOrNullComparable: Int? = values.maxOfOrNull { it.value }
    val maxOfOrNullDouble: Double? = values.maxOfOrNull { it.value.toDouble() }
    val maxOfOrNullFloat: Float? = values.maxOfOrNull { it.value.toFloat() }
    val maxOfWith: Int = values.maxOfWith(compareBy { it }, { it.value })
    val maxOfWithOrNull: Int? = values.maxOfWithOrNull(compareBy { it }, { it.value })
    val maxWith: Map.Entry<String, Int> = values.maxWith(compareBy { it.value })
    val maxWithOrNull: Map.Entry<String, Int>? = values.maxWithOrNull(compareBy { it.value })
    println(maxBy)
    println(maxOfComparable)
    println(maxOfDouble)
    println(maxOfFloat)
    println(maxOfOrNullComparable)
    println(maxOfOrNullDouble)
    println(maxOfOrNullFloat)
    println(maxOfWith)
    println(maxOfWithOrNull)
    println(maxWith)
    println(maxWithOrNull)
}
