data class User(val name: String, val nickname: String?)

fun main() {
    val users = listOf(User("Alice", "A"), User("Bob", null), User("Carol", "A"))
    val byNickname = users.distinctBy { it.nickname }
    println(byNickname)
}
