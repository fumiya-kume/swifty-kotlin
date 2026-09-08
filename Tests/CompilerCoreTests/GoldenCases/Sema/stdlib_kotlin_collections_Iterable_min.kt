fun exercise(
    ints: Iterable<Int>,
    doubles: Iterable<Double>,
    floats: Iterable<Float>,
    nullableStrings: Iterable<String?>,
    comparator: Comparator<Number>
) {
    val minDouble: Double = doubles.min()
    val minFloat: Float = floats.min()
    val minComparable: Int = ints.min()
    val minBy: String? = nullableStrings.minBy { it ?: "" }
    val minByOrNull: String? = nullableStrings.minByOrNull { it ?: "" }
    val minOfComparable: Int = ints.minOf { it }
    val minOfDouble: Double = ints.minOf { it.toDouble() }
    val minOfFloat: Float = ints.minOf { it.toFloat() }
    val minOfOrNullComparable: Int? = ints.minOfOrNull { it }
    val minOfOrNullDouble: Double? = ints.minOfOrNull { it.toDouble() }
    val minOfOrNullFloat: Float? = ints.minOfOrNull { it.toFloat() }
    val maxOfOrNullComparable = ints.maxOfOrNull { it }
    val minOfWith: Double = ints.minOfWith(comparator) { it.toDouble() }
    val minOfWithOrNull: Double? = ints.minOfWithOrNull(comparator) { it.toDouble() }
    val minOrNullDouble: Double? = doubles.minOrNull()
    val minOrNullFloat: Float? = floats.minOrNull()
    val minOrNullComparable: Int? = ints.minOrNull()
    val minWith: Int = ints.minWith(comparator)
    val minWithOrNull: Int? = ints.minWithOrNull(comparator)
    println(minDouble)
    println(minFloat)
    println(minComparable)
    println(minBy)
    println(minByOrNull)
    println(minOfComparable)
    println(minOfDouble)
    println(minOfFloat)
    println(minOfOrNullComparable)
    println(minOfOrNullDouble)
    println(minOfOrNullFloat)
    println(maxOfOrNullComparable)
    println(minOfWith)
    println(minOfWithOrNull)
    println(minOrNullDouble)
    println(minOrNullFloat)
    println(minOrNullComparable)
    println(minWith)
    println(minWithOrNull)
}

fun listOwner(values: List<Int>) {
    println(values.min())
    val maxOfOrNullComparable: Int? = values.maxOfOrNull { it }
    println(maxOfOrNullComparable)
}

fun setOwner(values: Set<Int>) {
    println(values.minOrNull())
}

fun sequenceOwner(values: Sequence<Int>) {
    println(values.minOrNull())
}
