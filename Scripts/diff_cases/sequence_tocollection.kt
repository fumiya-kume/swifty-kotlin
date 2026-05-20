fun main() {
    val listDestination = mutableListOf(0)
    val listResult = sequenceOf(1, 2, 3).toCollection(listDestination)
    listResult.add(4)
    println(listDestination)

    val setDestination = mutableSetOf(10, 2)
    val setResult = sequenceOf(1, 2, 2, 3).toCollection(setDestination)
    setResult.add(4)
    println(setDestination)
}
