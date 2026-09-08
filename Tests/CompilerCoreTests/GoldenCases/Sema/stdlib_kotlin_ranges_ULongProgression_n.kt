fun probe(label: String, progression: ULongProgression) {
    try {
        println("$label:first=${progression.first().toString()}")
    } catch (error: NoSuchElementException) {
        println("$label:first=${error.message}")
    }
    try {
        println("$label:last=${progression.last().toString()}")
    } catch (error: NoSuchElementException) {
        println("$label:last=${error.message}")
    }
    println("$label:orNull=${progression.firstOrNull()},${progression.lastOrNull()}")
}

fun main() {
    val positive = ULongProgression.fromClosedRange(2uL, 11uL, 3)
    val negative = 10uL downTo 0uL step 3
    val emptyPositive = ULongProgression.fromClosedRange(5uL, 1uL, 1)
    val emptyNegative = ULongProgression.fromClosedRange(1uL, 5uL, -1)
    val minValue = ULongProgression.fromClosedRange(ULong.MIN_VALUE, ULong.MIN_VALUE, 1)
    val maxValue = ULongProgression.fromClosedRange(ULong.MAX_VALUE, ULong.MAX_VALUE, 1)

    println("properties=${positive.first},${positive.last}")
    println("positive=${positive.first().toString()},${positive.firstOrNull()},${positive.last().toString()},${positive.lastOrNull()}")
    println("negative=${negative.first().toString()},${negative.firstOrNull()},${negative.last().toString()},${negative.lastOrNull()}")
    println("min=${minValue.first().toString()},${minValue.firstOrNull()},${minValue.last().toString()},${minValue.lastOrNull()}")
    println("max=${maxValue.first().toString()},${maxValue.firstOrNull()},${maxValue.last().toString()},${maxValue.lastOrNull()}")
    probe("emptyPositive", emptyPositive)
    probe("emptyNegative", emptyNegative)
}
