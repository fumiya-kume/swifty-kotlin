// STDLIB-REFL-174: self-contained KSP-like basic flow for diff_kotlinc.
// The actual compiler support is verified in KSPSyntheticStubTests.

interface SymbolProcessor {
    fun process(resolver: Resolver): List<String>
}

class KSPLogger {
    fun info(message: String) {
        println("INFO:" + message)
    }
}

class Resolver(
    private val expectedAnnotation: String,
    private val symbolName: String
) {
    fun getAllSymbols(): List<String> = listOf(symbolName)

    fun getSymbolsWithAnnotation(annotationName: String): List<String> =
        if (annotationName == expectedAnnotation) listOf(symbolName) else emptyList()
}

class CodeGenerator(
    private val generatedName: String
) {
    fun generatedFiles(): List<String> = listOf(generatedName)
}

object ProcessorRegistry {
    fun register(name: String) {
        println("registered:" + name)
    }

    fun runAll(logger: KSPLogger): List<String> {
        logger.info("run:DemoProcessor")
        return listOf("DemoProcessor")
    }
}

class DemoProcessor : SymbolProcessor {
    override fun process(resolver: Resolver): List<String> {
        return resolver.getSymbolsWithAnnotation("Demo")
    }
}

fun main() {
    val logger = KSPLogger()
    val resolver = Resolver("Demo", "FirstSymbol")
    val codeGenerator = CodeGenerator("demo.generated.HelloGen")
    val processor = DemoProcessor()

    ProcessorRegistry.register("DemoProcessor")

    println("matched=" + processor.process(resolver).joinToString(","))
    println("executed=" + ProcessorRegistry.runAll(logger).joinToString(","))
    println("generated=" + codeGenerator.generatedFiles().joinToString(","))
    println("symbols=" + resolver.getAllSymbols().joinToString(","))
}
