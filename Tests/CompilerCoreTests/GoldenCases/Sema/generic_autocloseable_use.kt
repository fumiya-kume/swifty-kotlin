package golden.sema

// STDLIB-030-BUG-01: generic upper bound <T : AutoCloseable> should allow .use {}
// AutoCloseable is a typealias to kotlin.io.Closeable; the constraint solver must
// expand the alias before checking upper-bound satisfaction and member lookup.

class MyAutoResource : AutoCloseable {
    override fun close() {}
}

fun <T : AutoCloseable> useIt(t: T): Unit {
    t.use { }
}

fun callSite(): Unit {
    useIt(MyAutoResource())
}
