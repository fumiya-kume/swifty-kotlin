fun main() {
    println(5 in 1..10)
    println(15 in 1..10)
    println(5 !in 1..10)
    println(15 !in 1..10)
    println('c' in 'a'..'z')
    println('A' in 'a'..'z')
    val list = listOf(1, 2, 3)
    println(2 in list)
    println(5 in list)
    println(5 !in list)
}
