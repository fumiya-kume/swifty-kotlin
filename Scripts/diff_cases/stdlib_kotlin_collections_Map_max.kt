private fun reportEmpty(label: String, action: () -> Unit) {
    try {
        action()
        println("$label=returned")
    } catch (e: NoSuchElementException) {
        println("$label=NoSuchElementException:${e.message}")
    }
}

fun main() {
    val ordered = linkedMapOf("first" to 2, "tie" to 2, "low" to 1)
    val projected: Map<out String, Int> = ordered
    val empty = emptyMap<String, Int>()
    val single = linkedMapOf("only" to 7)

    println("maxBy=${projected.maxBy { it.value }.key}")
    println("maxOf=${projected.maxOf { it.value }}")
    println("maxOfDouble=${projected.maxOf { it.value.toDouble() }}")
    println("maxOfFloat=${projected.maxOf { it.value.toFloat() }}")
    println("maxOfOrNull=${projected.maxOfOrNull { it.value }}")
    println("maxOfDoubleOrNull=${projected.maxOfOrNull { it.value.toDouble() }}")
    println("maxOfFloatOrNull=${projected.maxOfOrNull { it.value.toFloat() }}")

    val ascending = Comparator<Int> { first, second -> first.compareTo(second) }
    val entryAscending = Comparator<Map.Entry<String, Int>> { first, second ->
        first.value.compareTo(second.value)
    }
    println("maxOfWith=${projected.maxOfWith(ascending) { it.value }}")
    println("maxOfWithOrNull=${projected.maxOfWithOrNull(ascending) { it.value }}")
    println("maxWith=${projected.maxWith(entryAscending)?.key}")
    println("maxWithOrNull=${projected.maxWithOrNull(entryAscending)?.key}")

    var maxByCalls = 0
    var maxOfCalls = 0
    var maxOfWithCalls = 0
    var maxWithCalls = 0
    single.maxBy { maxByCalls++; it.value }
    single.maxOf { maxOfCalls++; it.value }
    single.maxOfWith(ascending) { maxOfWithCalls++; it.value }
    single.maxWith(Comparator<Map.Entry<String, Int>> { first, second ->
        maxWithCalls++
        first.value.compareTo(second.value)
    })
    println("singleCalls=$maxByCalls:$maxOfCalls:$maxOfWithCalls:$maxWithCalls")

    println("emptyOrNull=${empty.maxOfOrNull { it.value }}:${empty.maxWithOrNull(entryAscending)}")
    reportEmpty("maxBy-empty") { empty.maxBy { it.value } }
    reportEmpty("maxOf-empty") { empty.maxOf { it.value } }
    reportEmpty("maxOfWith-empty") { empty.maxOfWith(ascending) { it.value } }
    reportEmpty("maxWith-empty") { empty.maxWith(entryAscending) }

    val floating = linkedMapOf(
        "negInf" to Double.NEGATIVE_INFINITY,
        "nan" to Double.NaN,
        "posInf" to Double.POSITIVE_INFINITY
    )
    println("doubleNaN=${floating.maxOf { it.value }.isNaN()}")
    println("floatNaN=${floating.maxOf { it.value.toFloat() }.isNaN()}")
    println("doubleZeroBits=${linkedMapOf("neg" to -0.0, "pos" to 0.0).maxOf { it.value }.toRawBits()}")
    println("floatZeroBits=${linkedMapOf("neg" to -0.0f, "pos" to 0.0f).maxOf { it.value }.toRawBits()}")

    val nullable = linkedMapOf<String?, Int?>(null to null, "value" to -3)
    println("nullable=${nullable.maxBy { it.value ?: Int.MIN_VALUE }?.key}")
    println("negative=${linkedMapOf("a" to -10, "b" to -1).maxOf { it.value }}")
}
