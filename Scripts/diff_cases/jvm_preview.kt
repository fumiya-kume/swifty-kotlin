// STDLIB-JVM-166: Java preview feature simulations.
// Covers: @PreviewFeature opt-in, sealed class hierarchy, @JvmRecord, pattern
// matching for instanceof, switch expressions, and text blocks.

// ---------------------------------------------------------------------------
// Sealed class hierarchy interop
// ---------------------------------------------------------------------------
sealed class Shape
data class Circle(val radius: Double) : Shape()
data class Rectangle(val width: Double, val height: Double) : Shape()
data class Triangle(val base: Double, val height: Double) : Shape()

fun describeShape(shape: Shape): String = when (shape) {
    is Circle -> "circle with radius ${shape.radius}"
    is Rectangle -> "rectangle ${shape.width}x${shape.height}"
    is Triangle -> "triangle base=${shape.base} height=${shape.height}"
}

fun shapeArea(shape: Shape): Double = when (shape) {
    is Circle -> Math.PI * shape.radius * shape.radius
    is Rectangle -> shape.width * shape.height
    is Triangle -> 0.5 * shape.base * shape.height
}

// ---------------------------------------------------------------------------
// Java Records simulation via data classes with @JvmRecord
// ---------------------------------------------------------------------------
@JvmRecord
data class Point(val x: Int, val y: Int)

@JvmRecord
data class NamedRange(val name: String, val start: Int, val end: Int) {
    val length: Int get() = end - start
}

// ---------------------------------------------------------------------------
// Pattern matching for instanceof (smart cast)
// ---------------------------------------------------------------------------
fun typeLabel(obj: Any): String = when (obj) {
    is String -> "String(${obj.length})"
    is Int -> "Int($obj)"
    is Double -> "Double($obj)"
    is List<*> -> "List(size=${obj.size})"
    is Circle -> "Circle(r=${obj.radius})"
    else -> "Unknown"
}

// ---------------------------------------------------------------------------
// Switch expressions (when as expression — maps to JVM switch)
// ---------------------------------------------------------------------------
fun dayKind(day: String): String = when (day.uppercase()) {
    "SATURDAY", "SUNDAY" -> "weekend"
    "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY" -> "weekday"
    else -> "unknown"
}

fun httpStatusMessage(code: Int): String = when (code) {
    200 -> "OK"
    201 -> "Created"
    400 -> "Bad Request"
    401 -> "Unauthorized"
    403 -> "Forbidden"
    404 -> "Not Found"
    500 -> "Internal Server Error"
    else -> "Unknown ($code)"
}

// ---------------------------------------------------------------------------
// Text blocks (multi-line string literals)
// ---------------------------------------------------------------------------
val jsonTemplate: String = """
    {
        "name": "KSwiftK",
        "version": "1.0",
        "preview": true
    }
    """.trimIndent()

val sqlQuery: String = """
    SELECT id, name, value
    FROM items
    WHERE active = 1
    ORDER BY name ASC
    """.trimIndent()

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
fun main() {
    // Sealed classes
    val shapes: List<Shape> = listOf(
        Circle(3.0),
        Rectangle(4.0, 5.0),
        Triangle(6.0, 8.0)
    )
    for (shape in shapes) {
        println(describeShape(shape))
    }

    // Records (data classes)
    val p = Point(10, 20)
    println("point=${p.x},${p.y}")
    println("point=$p")
    val r1 = NamedRange("alpha", 0, 10)
    val r2 = NamedRange("alpha", 0, 10)
    println("range=${r1.name} len=${r1.length}")
    println("equal=${r1 == r2}")

    // Pattern matching
    val objects: List<Any> = listOf("hello", 42, 3.14, listOf(1, 2, 3), Circle(1.0), true)
    for (obj in objects) {
        println(typeLabel(obj))
    }

    // Switch expressions
    val days = listOf("Monday", "Saturday", "Sunday", "Wednesday", "Holiday")
    for (d in days) {
        println("$d -> ${dayKind(d)}")
    }
    val codes = listOf(200, 201, 404, 500, 418)
    for (c in codes) {
        println("$c -> ${httpStatusMessage(c)}")
    }

    // Text blocks
    println(jsonTemplate)
    println(sqlQuery)
}
