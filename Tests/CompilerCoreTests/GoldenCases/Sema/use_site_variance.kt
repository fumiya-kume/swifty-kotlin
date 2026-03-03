package golden.sema

class E

class Box<T> {
    fun get(): T = throw E()
    fun set(v: T) {}
}

fun readOnly(box: Box<out Any>): Any = box.get()

fun writeBlocked(box: Box<out Any>) {
    box.set(42)
}

fun writeOnly(box: Box<in Int>) {
    box.set(42)
}

fun starRead(box: Box<*>): Any? = box.get()

fun starReadInferred(box: Box<*>) {
    val x = box.get()
}

fun starWrite(box: Box<*>) {
    box.set(42)
}
