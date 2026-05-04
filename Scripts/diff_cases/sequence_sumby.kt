fun main() {
    val values = sequenceOf(1, 2, 3)
    println(values.sumBy { value ->
        if (value == 2) 10 else value
    })
    println(emptySequence<Int>().sumBy { 5 })
}
