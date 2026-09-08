fun printEmpty(label: String, progression: LongProgression) {
    try {
        progression.first()
        println("$label:first-returned")
    } catch (error: NoSuchElementException) {
        println("$label:first=${error.message}")
    }
    try {
        progression.last()
        println("$label:last-returned")
    } catch (error: NoSuchElementException) {
        println("$label:last=${error.message}")
    }
    println("$label:orNull=${progression.firstOrNull()},${progression.lastOrNull()}")
}

fun main() {
    val positive = LongProgression.fromClosedRange(2L, 11L, 3)
    val negative = 10L downTo -10L step 3
    val emptyPositive = LongProgression.fromClosedRange(5L, 1L, 1)
    val emptyNegative = LongProgression.fromClosedRange(1L, 5L, -1)
    val minValue = LongProgression.fromClosedRange(Long.MIN_VALUE, Long.MIN_VALUE, 1)
    val maxValue = LongProgression.fromClosedRange(Long.MAX_VALUE, Long.MAX_VALUE, 1)

    println("properties=${positive.first},${positive.last}")
    println("positive=${positive.first().toString()},${positive.firstOrNull()},${positive.last().toString()},${positive.lastOrNull()}")
    println("negative=${negative.first().toString()},${negative.firstOrNull()},${negative.last().toString()},${negative.lastOrNull()}")
    println("min=${minValue.first().toString()},${minValue.firstOrNull()},${minValue.last().toString()},${minValue.lastOrNull()}")
    println("max=${maxValue.first().toString()},${maxValue.firstOrNull()},${maxValue.last().toString()},${maxValue.lastOrNull()}")
    printEmpty("positive", emptyPositive)
    printEmpty("negative", emptyNegative)
}
