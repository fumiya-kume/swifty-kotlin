fun mapFilterToCase(source: Map<String, Int>, destination: MutableMap<Any?, Any?>): MutableMap<Any?, Any?> {
    return source.filterTo(destination) { entry -> entry.value > 1 }
}

fun mapFilterNotToCase(source: Map<String, Int>, destination: MutableMap<Any?, Any?>): MutableMap<Any?, Any?> {
    return source.filterNotTo(destination) { entry -> entry.value > 1 }
}
