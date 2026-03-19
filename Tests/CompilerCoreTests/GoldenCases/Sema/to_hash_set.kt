fun main() {
    val items = listOf("a", "b", "c")
    val hs: MutableSet<String> = items.toHashSet()
    hs.add("d")
    hs.remove("a")
    println(hs)
}
