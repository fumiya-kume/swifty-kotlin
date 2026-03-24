data class Person(val name: String, val age: Int)
fun main() {
    val p = Person("Alice", 30)
    println(p.toString())
    println(p.hashCode() != 0)
    val p2 = Person("Alice", 30)
    println(p == p2)
    println(p.equals(p2))
    val (name, age) = p
    println("$name is $age")
    println(p.component1())
    println(p.component2())
    val p3 = p.copy(age = 31)
    println(p3)
}
