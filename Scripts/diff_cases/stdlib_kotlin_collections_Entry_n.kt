fun main() {
    val values = linkedMapOf("a" to 1, "b" to 2)
    for (entry in values.entries) {
        println(entry.component1())
        println(entry.component2())
        println(entry.toPair())
    }

    val (firstKey, firstValue) = values.entries.first()
    println("$firstKey=$firstValue")

    for ((key, value) in values) {
        println("$key=$value")
    }
}
