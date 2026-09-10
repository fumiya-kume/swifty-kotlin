fun printEmpty(label: String, progression: IntProgression) {
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
}

fun main() {
    val positive = IntProgression.fromClosedRange(2, 11, 3)
    val negative = 10 downTo -10 step 3
    val emptyPositive = IntProgression.fromClosedRange(5, 1, 1)
    val emptyNegative = IntProgression.fromClosedRange(1, 5, -1)
    val minValue = IntProgression.fromClosedRange(Int.MIN_VALUE, Int.MIN_VALUE, 1)
    val maxValue = IntProgression.fromClosedRange(Int.MAX_VALUE, Int.MAX_VALUE, 1)

    println("properties=${positive.first},${positive.last}")
    println("positive=${positive.first()},${positive.last()}")
    println("negative=${negative.first()},${negative.last()}")
    println("min=${minValue.first()},${minValue.last()}")
    println("max=${maxValue.first()},${maxValue.last()}")
    printEmpty("positive", emptyPositive)
    printEmpty("negative", emptyNegative)
}
