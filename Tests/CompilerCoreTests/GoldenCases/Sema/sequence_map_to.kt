fun main() {
    val seq = sequenceOf(1, 2, 3, 4)

    val dest1 = mutableListOf<String>()
    val result1 = seq.mapTo(dest1) { it.toString() }
    println(result1)

    val dest2 = mutableListOf<String>()
    val result2 = seq.mapIndexedNotNullTo(dest2) { index, value ->
        if (index % 2 == 0) index.toString() + ":" + value.toString() else null
    }
    println(result2)
}
