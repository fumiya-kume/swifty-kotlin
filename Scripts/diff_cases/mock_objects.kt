interface CounterService {
    fun tick(value: Int): Int
}

interface Matcher {
    fun matches(value: Int): Boolean
}

class EqMatcher(private val expected: Int) : Matcher {
    override fun matches(value: Int): Boolean = value == expected
}

object AnyMatcher : Matcher {
    override fun matches(value: Int): Boolean = true
}

fun eq(value: Int): Matcher = EqMatcher(value)

fun any(): Matcher = AnyMatcher

class MockCounterService : CounterService {
    private class Stub(val matcher: Matcher) {
        val returns = mutableListOf<Int>()
    }

    inner class StubBuilder(private val stub: Stub) {
        fun thenReturn(value: Int) {
            stub.returns.add(value)
        }
    }

    private val stubs = mutableListOf<Stub>()
    val calls = mutableListOf<Int>()

    fun whenever(matcher: Matcher): StubBuilder {
        val stub = Stub(matcher)
        stubs.add(stub)
        return StubBuilder(stub)
    }

    override fun tick(value: Int): Int {
        calls.add(value)
        var index = stubs.size - 1
        while (index >= 0) {
            val stub = stubs[index]
            if (stub.matcher.matches(value) && stub.returns.isNotEmpty()) {
                if (stub.returns.size == 1) {
                    return stub.returns[0]
                }
                return stub.returns.removeAt(0)
            }
            index -= 1
        }
        return 0
    }

    fun verify(matcher: Matcher): Int {
        var count = 0
        for (value in calls) {
            if (matcher.matches(value)) {
                count += 1
            }
        }
        return count
    }
}

class SpyCounterService(private val base: CounterService) : CounterService by base {
    val calls = mutableListOf<Int>()

    override fun tick(value: Int): Int {
        calls.add(value)
        return base.tick(value)
    }
}

fun main() {
    val mock = MockCounterService()
    val stub = mock.whenever(eq(7))
    stub.thenReturn(10)
    stub.thenReturn(20)
    println(mock.tick(7))
    println(mock.tick(7))
    println(mock.tick(3))
    println(mock.verify(eq(7)))

    val wildcard = MockCounterService()
    wildcard.whenever(any()).thenReturn(99)
    println(wildcard.tick(1))
    println(wildcard.verify(any()))

    val spy = SpyCounterService(object : CounterService {
        override fun tick(value: Int): Int = value * 2
    })
    println(spy.tick(4))
    println(spy.calls.size)
}
