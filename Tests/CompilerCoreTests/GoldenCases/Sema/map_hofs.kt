fun render(values: Map<String, Int>) {
    values.forEach { (key, value) ->
        println(key)
        println(value)
    }
    println(values.map { (key, value) -> key.length + value })
    println(values.filter { (_, value) -> value > 1 })
    println(values.mapValues { it.value * 2 })
    println(values.mapKeys { it.key + "!" })
    println(values.toList())
}
