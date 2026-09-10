fun render(values: Map<String, Int?>) {
    println(values.size)
    println(values.keys)
    println(values.values)
    println(values.entries)
    println(values.isEmpty())
    println(values["a"])
}

fun renderHashMap() {
    val values = HashMap<String, Int?>()
    values["a"] = 1
    values["b"] = null
    println(values.size)
    println(values.keys)
    println(values.values)
    println(values.entries)
    println(values.isEmpty())
    println(values["a"])
}

fun main() {
    render(mapOf("a" to 1, "b" to null))
    render(emptyMap<String, Int?>())
    renderHashMap()
}
