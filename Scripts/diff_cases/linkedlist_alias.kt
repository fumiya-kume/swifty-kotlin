// SKIP-DIFF
fun main() {
    val list: LinkedList<String> = LinkedList()
    list.add("hello")
    list.add("world")
    println(list)
    println(list.size)
    list.removeAt(0)
    println(list)
    list.add(0, "hi")
    println(list)
    println(list.first())
    println(list.last())
}
