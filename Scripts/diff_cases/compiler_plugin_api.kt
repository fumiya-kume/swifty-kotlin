// SKIP-DIFF
// STDLIB-REFL-173: compiler plugin API baseline
// Exercises CommandProcessor, ExtensionRegistrar, IrGenerationExtension,
// ClassBuilderInterceptor, and plugin metadata storage in a self-contained
// pure-Kotlin fixture compatible with diff_kotlinc.sh.

interface CommandProcessor {
    val pluginId: String
    val displayName: String
    fun processOption(key: String, value: String)
}

interface ExtensionRegistrar {
    val pluginId: String
    fun registerExtension(name: String, kind: String)
}

interface IrGenerationExtension {
    val name: String
    fun generate(moduleName: String)
}

interface ClassBuilderInterceptor {
    val name: String
    fun intercept(className: String)
}

data class PluginMetadata(
    val pluginId: String,
    val displayName: String,
    val version: String,
    val commandProcessorName: String? = null,
    val registrarName: String? = null,
    val registeredExtensions: List<String> = emptyList(),
    val options: Map<String, String> = emptyMap(),
    val generatedModules: List<String> = emptyList(),
    val interceptedClasses: List<String> = emptyList()
)

object PluginRegistry {
    private val plugins = mutableMapOf<String, PluginMetadata>()

    fun register(pluginId: String, displayName: String, version: String): PluginMetadata {
        val entry = PluginMetadata(
            pluginId = pluginId,
            displayName = displayName,
            version = version
        )
        plugins[pluginId] = entry
        return entry
    }

    fun lookup(pluginId: String): PluginMetadata? = plugins[pluginId]

    fun update(pluginId: String, block: (PluginMetadata) -> PluginMetadata) {
        val current = plugins[pluginId] ?: PluginMetadata(pluginId, pluginId, "")
        plugins[pluginId] = block(current)
    }
}

class MyCommandProcessor(
    override val pluginId: String,
    override val displayName: String
) : CommandProcessor {
    override fun processOption(key: String, value: String) {
        PluginRegistry.update(pluginId) { m ->
            m.copy(
                commandProcessorName = displayName,
                options = m.options + (key to value)
            )
        }
        println("processed:$key=$value")
    }
}

class MyExtensionRegistrar(override val pluginId: String) : ExtensionRegistrar {
    override fun registerExtension(name: String, kind: String) {
        PluginRegistry.update(pluginId) { m ->
            val updated = if (m.registeredExtensions.contains("$kind:$name")) {
                m.registeredExtensions
            } else {
                m.registeredExtensions + "$kind:$name"
            }
            m.copy(registrarName = name, registeredExtensions = updated)
        }
        println("registered:$kind:$name")
    }
}

class MyIrGenerationExtension(override val name: String, val pluginId: String) : IrGenerationExtension {
    override fun generate(moduleName: String) {
        PluginRegistry.update(pluginId) { m ->
            m.copy(generatedModules = m.generatedModules + moduleName)
        }
        println("generated:$moduleName")
    }
}

class MyClassBuilderInterceptor(override val name: String, val pluginId: String) : ClassBuilderInterceptor {
    override fun intercept(className: String) {
        PluginRegistry.update(pluginId) { m ->
            m.copy(interceptedClasses = m.interceptedClasses + className)
        }
        println("intercepted:$className")
    }
}

fun main() {
    val pluginId = "com.example.demo-plugin"

    // Register plugin metadata
    PluginRegistry.register(pluginId, "Demo Plugin", "1.0.0")

    // CommandProcessor
    val processor = MyCommandProcessor(pluginId, "DemoCommandProcessor")
    processor.processOption("output", "build/generated")
    processor.processOption("verbose", "true")

    // ExtensionRegistrar
    val registrar = MyExtensionRegistrar(pluginId)
    registrar.registerExtension("DemoIrExt", "ir-generation")
    registrar.registerExtension("DemoCBIExt", "class-builder-interceptor")

    // IrGenerationExtension
    val irExt = MyIrGenerationExtension("DemoIrExt", pluginId)
    irExt.generate("app")
    irExt.generate("lib")

    // ClassBuilderInterceptor
    val interceptor = MyClassBuilderInterceptor("DemoCBIExt", pluginId)
    interceptor.intercept("com.example.UserModel")
    interceptor.intercept("com.example.AuditModel")

    // Verify metadata
    val meta = PluginRegistry.lookup(pluginId)
    println("pluginId=${meta?.pluginId}")
    println("displayName=${meta?.displayName}")
    println("version=${meta?.version}")
    println("commandProcessorName=${meta?.commandProcessorName}")
    println("extensions=${meta?.registeredExtensions?.joinToString(",")}")
    println("generatedModules=${meta?.generatedModules?.joinToString(",")}")
    println("interceptedClasses=${meta?.interceptedClasses?.joinToString(",")}")
    println("options=${meta?.options?.entries?.sortedBy { it.key }?.joinToString(",") { "${it.key}=${it.value}" }}")
}
