package golden.sema

fun useBuildStringReceiverThis(): String = buildString {
    this.append("a")
    append("b")
}

fun useBuildListReceiverThis(): Any = buildList {
    this.add(1)
    add(2)
}
