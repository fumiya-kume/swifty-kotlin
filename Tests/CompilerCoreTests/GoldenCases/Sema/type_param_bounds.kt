package golden.sema

open class Animal
class Dog : Animal()

fun <T : Animal> accept(x: T): T = x
fun callValid(): Animal = accept(Dog())
fun <T> unbounded(x: T): T = x
fun callUnbounded(): Int = unbounded(42)

fun <T : Animal> acceptWhere(x: T): T where T : Animal = x
