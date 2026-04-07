fun main() {
    val set = setOf(2, 4, 6, 8)
    println(set.all { it % 2 == 0 })   // true
    println(set.all { it > 5 })         // false
    println(set.any { it > 5 })         // true
    println(set.any { it > 100 })       // false
    println(set.none { it < 0 })        // true
    println(set.none { it == 4 })       // false
    println(set.count { it > 4 })       // 2
}
