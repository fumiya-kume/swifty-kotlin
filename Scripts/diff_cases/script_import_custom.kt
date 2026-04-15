// SKIP-DIFF
// カスタム拡張関数
fun String.isPalindrome(): Boolean {
    return this == this.reversed()
}

// データクラス
data class Person(val name: String, val age: Int)

fun Person.isAdult(): Boolean = age >= 18

val text = "level"
val person = Person("Alice", 25)

println("'$text' is palindrome: ${text.isPalindrome()}")
println("${person.name} is adult: ${person.isAdult()}")
