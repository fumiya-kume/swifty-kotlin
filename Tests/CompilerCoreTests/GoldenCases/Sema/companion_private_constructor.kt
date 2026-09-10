// RF-FIXTURE-021: private constructors (plain class and data class) invoked
// from the class's own companion factory — the companion is allowed to call
// the private constructor. Runtime factory output is executed by
// Scripts/diff_cases/companion_private_access.kt.
package golden.sema

class User private constructor(private val name: String, private val age: Int) {
    companion object {
        fun createAdult(name: String): User = User(name, 18)
        fun fromNameAndAge(name: String, age: Int): User = User(name, age)
    }
}

data class Product private constructor(
    private val id: String,
    private val price: Double
) {
    companion object {
        fun create(id: String, price: Double): Product = Product(id, price)
    }
}
