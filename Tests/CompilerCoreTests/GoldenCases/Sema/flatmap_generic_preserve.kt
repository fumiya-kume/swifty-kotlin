fun flatMapGeneric(names: List<String>) {
    val lengths: List<Int> = names.flatMap { listOf(it.length) }
    val chars: List<String> = names.flatMap { listOf(it, it.uppercase()) }
    val doubled = names.flatMap { listOf(it.length, it.length * 2) }
    println(lengths)
    println(chars)
    println(doubled)
}
