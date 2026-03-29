package testframework

import kotlin.test.After
import kotlin.test.Before
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TestFrameworkBasicSuite {
    private val events = mutableListOf<String>()

    @Before
    fun setUp() {
        events += "before"
    }

    @After
    fun tearDown() {
        events += "after"
    }

    @Test
    fun testAssertions() {
        assertEquals(1, 1)
        assertEquals("hello", "he" + "llo")
        assertTrue(events.isNotEmpty())
        assertNull(null)
    }

    fun run() {
        setUp()
        testAssertions()
        tearDown()
    }
}

fun main() {
    TestFrameworkBasicSuite().run()
    println("test framework basic ok")
}
