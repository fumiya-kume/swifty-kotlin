package golden.sema

fun exerciseMapEntryMembers(values: Map<String, Int>): Pair<String, Int> {
    val entry = values.entries.first()
    val key = entry.component1()
    val value = entry.component2()
    return entry.toPair()
}

fun destructureMapEntryInValDecl(values: Map<String, Int>): String {
    val (key, value) = values.entries.first()
    return "$key=$value"
}

fun destructureMapEntryInForLoop(values: Map<String, Int>): String {
    var result = ""
    for ((key, value) in values) {
        result += "$key=$value;"
    }
    return result
}
