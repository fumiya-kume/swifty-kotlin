fun main() {
    val values = sequenceOf(1, 2, 3)
    println(values.sumByDouble { value ->
        if (value == 2) 1.5 else 0.25
    })
    println(emptySequence<Int>().sumByDouble { 5.0 })
}
