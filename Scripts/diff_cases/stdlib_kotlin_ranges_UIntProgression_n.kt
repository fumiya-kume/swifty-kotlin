fun printEmpty(label: String, progression: UIntProgression) {
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
    val positive = UIntProgression.fromClosedRange(2u, 11u, 3)
    val negative = 10u downTo 1u step 3
    val emptyPositive = UIntProgression.fromClosedRange(10u, 1u, 3)
    val emptyNegative = UIntProgression.fromClosedRange(1u, 10u, -3)
    val minValue = UIntProgression.fromClosedRange(UInt.MIN_VALUE, UInt.MIN_VALUE, 1)
    val maxValue = UIntProgression.fromClosedRange(UInt.MAX_VALUE, UInt.MAX_VALUE, 1)

    println("properties=${positive.first},${positive.last}")
    println("positive=${positive.first().toString()},${positive.firstOrNull()},${positive.last().toString()},${positive.lastOrNull()}")
    println("negative=${negative.first().toString()},${negative.firstOrNull()},${negative.last().toString()},${negative.lastOrNull()}")
    println("min=${minValue.first().toString()},${minValue.firstOrNull()},${minValue.last().toString()},${minValue.lastOrNull()}")
    println("max=${maxValue.first().toString()},${maxValue.firstOrNull()},${maxValue.last().toString()},${maxValue.lastOrNull()}")
    printEmpty("positive", emptyPositive)
    printEmpty("negative", emptyNegative)
}
