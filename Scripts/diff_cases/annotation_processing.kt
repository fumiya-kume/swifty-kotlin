// STDLIB-REFL-175: Advanced Annotation Processing
// Fixture for KAPT-style processing scenarios:
// - multiple annotated declarations
// - processor options
// - generated type targets

@Target(AnnotationTarget.CLASS)
@Retention(AnnotationRetention.RUNTIME)
annotation class GenerateAdapter(val name: String)

@Target(AnnotationTarget.CLASS)
@Retention(AnnotationRetention.RUNTIME)
annotation class ProcessorOption(val key: String, val value: String)

@GenerateAdapter("UserAdapter")
@ProcessorOption("mode", "incremental")
class UserModel

@GenerateAdapter("AuditAdapter")
class AuditModel

fun main() {
    val inputs = listOf(UserModel::class.simpleName, AuditModel::class.simpleName)
    println("annotation processing inputs: ${inputs.joinToString()}")
    println("expected generated: UserAdapter, AuditAdapter")
    println("expected option: mode=incremental")
}
