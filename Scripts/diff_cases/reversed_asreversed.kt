fun main() {
    val list = listOf(1, 2, 3, 4, 5)
    println(list.reversed())
    println(list.asReversed())
    val mutable = mutableListOf(1, 2, 3)
    println(mutable.reversed())
    val rev = mutable.asReversed()
    println(rev)
    mutable[0] = 10
    println(rev)
    println(listOf<Int>().reversed())
    println(listOf<Int>().asReversed())
}
