import Foundation
@testable import Runtime
import XCTest

final class CompilerPluginRuntimeTests: IsolatedRuntimeXCTestCase {
    private func makeRuntimeString(_ value: String) -> Int {
        let utf8 = Array(value.utf8)
        if utf8.isEmpty {
            var emptyByte: UInt8 = 0
            return withUnsafePointer(to: &emptyByte) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, 0))
            }
        }
        return utf8.withUnsafeBufferPointer { buffer in
            Int(bitPattern: kk_string_from_utf8(buffer.baseAddress!, Int32(buffer.count)))
        }
    }

    private func makeRuntimeStringList(_ values: [String]) -> Int {
        registerRuntimeObject(RuntimeListBox(elements: values.map(makeRuntimeString)))
    }

    private func stringValue(from raw: Int) -> String? {
        guard raw != 0,
              raw != runtimeNullSentinelInt,
              let ptr = UnsafeMutableRawPointer(bitPattern: raw)
        else {
            return nil
        }
        if let list = tryCast(ptr, to: RuntimeListBox.self),
           let first = list.elements.first
        {
            return extractString(from: UnsafeMutableRawPointer(bitPattern: first))
        }
        return extractString(from: ptr)
    }

    private func stringList(from raw: Int) -> [String] {
        guard raw != 0,
              raw != runtimeNullSentinelInt,
              let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let list = tryCast(ptr, to: RuntimeListBox.self)
        else {
            return []
        }
        return list.elements.compactMap { extractString(from: UnsafeMutableRawPointer(bitPattern: $0)) }
    }

    func testCompilerPluginMetadataRegistrationAndLookup() {
        let metadataRaw = kk_compiler_plugin_register(
            makeRuntimeString("sample.plugin"),
            makeRuntimeString("Sample Plugin"),
            makeRuntimeString("1.0.0")
        )

        XCTAssertEqual(stringValue(from: kk_compiler_plugin_metadata_get_plugin_id(metadataRaw)), "sample.plugin")
        XCTAssertEqual(stringValue(from: kk_compiler_plugin_metadata_get_display_name(metadataRaw)), "Sample Plugin")
        XCTAssertEqual(stringValue(from: kk_compiler_plugin_metadata_get_version(metadataRaw)), "1.0.0")

        let lookedUp = kk_compiler_plugin_metadata_lookup(makeRuntimeString("sample.plugin"))
        XCTAssertNotEqual(lookedUp, runtimeNullSentinelInt)
        XCTAssertEqual(stringValue(from: kk_compiler_plugin_metadata_get_display_name(lookedUp)), "Sample Plugin")
    }

    func testCommandProcessorProcessesMatchingPluginOptions() {
        _ = kk_compiler_plugin_register(
            makeRuntimeString("sample.plugin"),
            makeRuntimeString("Sample Plugin"),
            makeRuntimeString("1.0.0")
        )
        let processorRaw = kk_command_processor_create(
            makeRuntimeString("sample.plugin"),
            makeRuntimeString("SampleProcessor"),
            makeRuntimeStringList(["enabled", "feature"])
        )

        let processed = kk_command_processor_process(
            processorRaw,
            makeRuntimeStringList([
                "-P plugin:sample.plugin:enabled=true",
                "feature.mode=strict",
                "-P plugin:other.plugin:enabled=false",
                "ignored.option=nope",
            ])
        )

        XCTAssertEqual(processed, 2)

        let metadataRaw = kk_compiler_plugin_metadata_lookup(makeRuntimeString("sample.plugin"))
        XCTAssertEqual(
            stringValue(from: kk_compiler_plugin_metadata_get_command_processor_name(metadataRaw)),
            "SampleProcessor"
        )
        XCTAssertEqual(
            stringList(from: kk_compiler_plugin_metadata_get_options(metadataRaw)),
            ["enabled=true", "feature.mode=strict"]
        )
    }

    func testExtensionRegistrarAndGenerationHooksPersistMetadata() {
        _ = kk_compiler_plugin_register(
            makeRuntimeString("sample.plugin"),
            makeRuntimeString("Sample Plugin"),
            makeRuntimeString("1.0.0")
        )
        let registrarRaw = kk_extension_registrar_create(
            makeRuntimeString("sample.plugin"),
            makeRuntimeString("SampleRegistrar")
        )
        XCTAssertEqual(
            kk_extension_registrar_register_extension(
                registrarRaw,
                makeRuntimeString("SampleIrExtension"),
                RuntimeCompilerPluginExtensionKind.irGeneration.allCasesIndex
            ),
            0
        )
        XCTAssertEqual(
            kk_extension_registrar_register_extension(
                registrarRaw,
                makeRuntimeString("SampleBuilderInterceptor"),
                RuntimeCompilerPluginExtensionKind.classBuilderInterceptor.allCasesIndex
            ),
            0
        )

        let irRaw = kk_ir_generation_extension_create(
            makeRuntimeString("sample.plugin"),
            makeRuntimeString("SampleIrExtension")
        )
        XCTAssertEqual(kk_ir_generation_extension_generate(irRaw, makeRuntimeString("main")), 0)
        XCTAssertEqual(kk_ir_generation_extension_generate(irRaw, makeRuntimeString("test")), 0)

        let interceptorRaw = kk_class_builder_interceptor_create(
            makeRuntimeString("sample.plugin"),
            makeRuntimeString("SampleBuilderInterceptor")
        )
        XCTAssertEqual(kk_class_builder_interceptor_intercept(interceptorRaw, makeRuntimeString("com.example.Foo")), 0)

        let metadataRaw = kk_compiler_plugin_metadata_lookup(makeRuntimeString("sample.plugin"))
        XCTAssertEqual(
            stringValue(from: kk_compiler_plugin_metadata_get_registrar_name(metadataRaw)),
            "SampleRegistrar"
        )
        XCTAssertEqual(
            stringList(from: kk_compiler_plugin_metadata_get_extensions(metadataRaw)).sorted(),
            [
                "class-builder-interceptor:SampleBuilderInterceptor",
                "ir-generation:SampleIrExtension",
            ]
        )
        XCTAssertEqual(
            stringList(from: kk_compiler_plugin_metadata_get_generated_modules(metadataRaw)),
            ["main", "test"]
        )
        XCTAssertEqual(
            stringList(from: kk_compiler_plugin_metadata_get_intercepted_classes(metadataRaw)),
            ["com.example.Foo"]
        )
    }

    func testRuntimeForceResetClearsPluginMetadata() {
        _ = kk_compiler_plugin_register(
            makeRuntimeString("sample.plugin"),
            makeRuntimeString("Sample Plugin"),
            makeRuntimeString("1.0.0")
        )
        XCTAssertNotEqual(
            kk_compiler_plugin_metadata_lookup(makeRuntimeString("sample.plugin")),
            runtimeNullSentinelInt
        )

        kk_runtime_force_reset()

        XCTAssertEqual(
            kk_compiler_plugin_metadata_lookup(makeRuntimeString("sample.plugin")),
            runtimeNullSentinelInt
        )
    }
}

private extension RuntimeCompilerPluginExtensionKind {
    var allCasesIndex: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}
