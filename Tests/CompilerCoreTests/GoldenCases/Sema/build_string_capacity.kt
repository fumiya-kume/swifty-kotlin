package golden.sema

fun useBuildStringWithCapacity(): String = buildString(capacity = 16) {
    append("hello")
    append(" world")
}

fun useBuildStringWithCapacityPositional(): String = buildString(32) {
    append("foo")
}
