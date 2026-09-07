fun main() {
    val source = mapOf("a" to 1, "b" to 2, "c" to 3)

    val filterDestination = mutableMapOf<Any?, Any?>("a" to 99, "seed" to 0)
    val filterResult: MutableMap<Any?, Any?> = source.filterTo(filterDestination) { it.value >= 2 }
    println("filterTo identity=${filterResult === filterDestination} value=$filterDestination")

    val filterNotDestination = mutableMapOf<Any?, Any?>("seed" to 0)
    val filterNotResult: MutableMap<Any?, Any?> = source.filterNotTo(filterNotDestination) { it.value >= 2 }
    println("filterNotTo identity=${filterNotResult === filterNotDestination} value=$filterNotDestination")

    val emptyDestination = mutableMapOf<Any?, Any?>("seed" to 0)
    val emptyResult = emptyMap<String, Int>().filterTo(emptyDestination) { true }
    println("empty identity=${emptyResult === emptyDestination} value=$emptyDestination")

    val nullableSource = mapOf<String?, Int?>(null to null, "value" to 2)
    val nullableDestination = mutableMapOf<Any?, Any?>("seed" to 0)
    val nullableResult: MutableMap<Any?, Any?> = nullableSource.filterNotTo(nullableDestination) { it.value == null }
    println("nullable identity=${nullableResult === nullableDestination} value=$nullableDestination")

    val interrupted = mutableMapOf<Any?, Any?>("seed" to 0)
    try {
        source.filterTo(interrupted) {
            if (it.key == "b") throw IllegalStateException("stop")
            true
        }
    } catch (exception: IllegalStateException) {
        println("exception=${exception.message} partial=$interrupted")
    }
}
