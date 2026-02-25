package golden.sema

typealias Predicate<T> = (T) -> Boolean
typealias Func<T> = (T) -> T
typealias StringAlias = String

fun usePredicate(p: Predicate<Int>) = p(42)
fun useFunc(f: Func<String>) = f("hello")
fun useAlias(s: StringAlias) = s
