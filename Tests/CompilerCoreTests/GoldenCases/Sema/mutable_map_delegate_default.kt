// RF-FIXTURE-019: MutableMap as a local property delegate, and withDefault /
// getValue on the read-through view.
fun mapDelegate(delegatedMap: MutableMap<String, Int>) {
    var delegated: Int by delegatedMap
    delegated = 31
    val read = delegated
    val checked: Int = read
}

fun withDefaultRead(map: MutableMap<String, Int>) {
    val defaulted = map.withDefault { key -> key.length }
    val value = defaulted.getValue("any")
    val checked: Int = value
}
