package golden.sema

open class Box<T>(val value: T) {
    fun get(): T = value
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
