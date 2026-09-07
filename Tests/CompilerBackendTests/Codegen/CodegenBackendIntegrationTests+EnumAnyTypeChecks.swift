#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// BUG-182: an enum constant widened to `Any` was boxed as a raw ordinal Int
/// (or, after BUG-177, as a RuntimeIntBox with only a display name). Because
/// the box carried no stable nominal type ID and the enum class had no runtime
/// supertype edges, `is`/`as`/`as?`/`!is`/`KClass.isInstance` against the
/// enum class (or `kotlin.Enum`/`kotlin.Comparable`) failed or panicked.
///
/// Fixed by passing the stable nominal type ID to `kk_enum_box_ordinal` and
/// by having `__enum_static_init_*` register the enum class's supertype edges
/// (`kotlin.Enum` and `kotlin.Comparable`) so the runtime assignability walk
/// can answer checks correctly.

@Suite
struct CodegenBackendEnumAnyTypeChecksTests {

    @Test
    func testCodegenEnumWidenedToAnyAnswersTypeChecks() throws {
        let source = """
        enum class Direction { NORTH, SOUTH, EAST, WEST }

        fun main() {
            val boxed: Any = Direction.WEST
            println(boxed is Direction)
            println(boxed is Enum<*>)
            println(boxed is Comparable<*>)
            println(boxed !is Direction)
            println(boxed as Direction)
            println(boxed as? Direction)
            println(Direction::class.isInstance(boxed))

            val other: Any = 42
            println(other is Direction)
            println(other as? Direction)
            println(Direction::class.isInstance(other))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumAnyTypeChecksMinimal",
            expected:
                """
                true
                true
                true
                false
                WEST
                WEST
                true
                false
                null
                false
                """
                + "\n"
        )
    }

    @Test
    func testCodegenMixedEnumClassesInAnyCollectionFilterCorrectly() throws {
        let source = """
        enum class Direction { NORTH, SOUTH }
        enum class Color { RED, GREEN }

        fun main() {
            val mixed: List<Any> = listOf(Direction.NORTH, Color.RED, Direction.SOUTH, Color.GREEN)
            println(mixed.filterIsInstance<Direction>())
            println(mixed.filterIsInstance<Color>())
            println(mixed.filterIsInstance<Enum<*>>().size)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumAnyFilterIsInstance",
            expected:
                """
                [NORTH, SOUTH]
                [RED, GREEN]
                4
                """
                + "\n"
        )
    }

    /// BUG-225: enum values use raw ordinal Ints internally, but a type check
    /// needs a nominally tagged box so the enum class and its interfaces can
    /// be recognized by `kk_op_is`/`kk_op_cast`.
    @Test
    func testCodegenStaticallyTypedEnumAnswersTypeChecks() throws {
        let source = """
        interface Labeled

        enum class Medal : Labeled { BRONZE, SILVER, GOLD }

        fun classifyMedal(medal: Medal): String =
            if (medal is Medal) "enum-yes" else "enum-no"

        fun classifyLabel(medal: Medal): String =
            if (medal is Labeled) "label-yes" else "label-no"

        fun main() {
            println(Medal.BRONZE is Medal)
            println(Medal.BRONZE is Labeled)

            val medal: Medal = Medal.SILVER
            println(medal is Medal)
            println(medal is Labeled)

            println(classifyMedal(Medal.GOLD))
            println(classifyLabel(Medal.GOLD))

            println(Medal.BRONZE as Medal)
            println(Medal.SILVER as? Medal)
            println(Medal.GOLD as Labeled)
            println(Medal.BRONZE as? Labeled)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumStaticTypeChecks",
            expected:
                """
                true
                true
                true
                true
                enum-yes
                label-yes
                BRONZE
                SILVER
                GOLD
                BRONZE
                """
                + "\n",
            allowDefaultStdlibLibrary: false
        )
    }
}
#endif
