fun main() {
    val set = buildSet {
        add(1)
        add(2)
        add(3)
        add(1)
    }
    println(set)
    println(set.size)
}
