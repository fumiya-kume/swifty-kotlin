fun greet(name: String, greeting: String = "Hello", punctuation: String = "!") = "$greeting, $name$punctuation"
fun main() {
    println(greet("Alice"))
    println(greet("Bob", "Hi"))
    println(greet("Charlie", punctuation = "."))
    println(greet(name = "Dave", punctuation = "?", greeting = "Hey"))
}
