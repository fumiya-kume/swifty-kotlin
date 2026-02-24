sealed class Animal
class Dog : Animal()
class Cat : Animal()
class Bird : Animal()

fun describeAnimal(a: Animal): String {
    return when (a) {
        is Dog -> "dog"
        is Cat -> "cat"
    }
}
