package golden.sema

import kotlin.reflect.KClass

class First
class Second

fun compareClasses(left: KClass<*>, right: Any?): Boolean =
    left.equals(right)

fun hashMatches(left: KClass<*>, right: KClass<*>): Boolean =
    left.hashCode() == right.hashCode()

fun operatorMatches(left: KClass<*>, right: KClass<*>): Boolean =
    left == right
