package golden.sema

open class Animal
class Dog : Animal()

fun <T : Animal> accept(x: T): T = x
fun callValid(): Animal = accept(Dog())
