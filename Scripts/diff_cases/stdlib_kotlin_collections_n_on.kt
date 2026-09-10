// KSP-957: exercise generic Iterable and Map on-family APIs, including action
// order and the identity-preserving return contract.
fun main() {
    val iterable: Iterable<Int> = listOf(10, 20, 30)

    var iterableTrace = ""
    val iterableResult = iterable.onEach { value -> iterableTrace += "$value;" }
    println(iterableTrace)
    println(iterableResult === iterable)

    var iterableIndexedTrace = ""
    val iterableIndexedResult = iterable.onEachIndexed { index, value ->
        iterableIndexedTrace += "$index:$value;"
    }
    println(iterableIndexedTrace)
    println(iterableIndexedResult === iterable)

    val map: Map<String, Int> = linkedMapOf("a" to 1, "b" to 2)

    var mapTrace = ""
    val mapResult = map.onEach { entry -> mapTrace += "${entry.key}=${entry.value};" }
    println(mapTrace)
    println(mapResult === map)

    var mapIndexedTrace = ""
    val mapIndexedResult = map.onEachIndexed { index, entry ->
        mapIndexedTrace += "$index:${entry.key}=${entry.value};"
    }
    println(mapIndexedTrace)
    println(mapIndexedResult === map)
}
