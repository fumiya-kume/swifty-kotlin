@testable import CompilerCore
import RuntimeABI
import Foundation
import Testing

@Suite
struct RuntimeABIExternalLinkValidationTests {
    @Test func testRegisteredSemaExternalLinkNamesExistInRuntimeABI() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let runtimeABINames = Set(RuntimeABISpec.allFunctions.map(\.name))
        let linkNames = Set(sema.symbols.allSymbols().compactMap { symbol in
            sema.symbols.externalLinkName(for: symbol.id)
        }.filter { !$0.isEmpty })
        let missing = linkNames
            .subtracting(runtimeABINames)
            .subtracting(allowedCompilerExternalLinks)
            .sorted()

        #expect(
            missing.isEmpty,
            Comment(rawValue: "Compiler synthetic externalLinkName values missing from RuntimeABISpec: \(missing.joined(separator: ", "))")
        )
    }

    @Test func testKIRHardcodedRuntimeLinkNamesExistInRuntimeABI() throws {
        let runtimeABINames = Set(RuntimeABISpec.allFunctions.map(\.name))
        let compilerCore = packageRoot().appendingPathComponent("Sources/CompilerCore")
        let linkNames = try collectRuntimeLinkNameLiterals(
            under: [
                compilerCore.appendingPathComponent("KIR"),
                compilerCore.appendingPathComponent("Lowering"),
                compilerCore.appendingPathComponent("Sema"),
            ]
        )
        let resolvedLinkNames = Set(linkNames)
        let missing = resolvedLinkNames
            .subtracting(runtimeABINames)
            .subtracting(allowedCompilerExternalLinks)
            .sorted()

        #expect(
            missing.isEmpty,
            Comment(rawValue: "KIR runtime link name literals missing from RuntimeABISpec: \(missing.joined(separator: ", "))")
        )
    }

    @Test func testBundledKsSymbolNameDeclarationsMatchRuntimeABIArity() throws {
        let annotatedDeclarations = try collectBundledKsSymbolNameDeclarations()
        let runtimeABIByName = Dictionary(grouping: RuntimeABISpec.allFunctions, by: \.name)
        var failures: [String] = []

        // Overloads (notably constructors) can share one link name, so a spec is
        // satisfied as soon as any declaration bound to that name matches it.
        for (linkName, declarations) in annotatedDeclarations.groupedByLinkName {
            guard let specs = runtimeABIByName[linkName], !specs.isEmpty else {
                let paths = declarations.relativePathList
                failures.append("\(linkName) in \(paths) is missing from RuntimeABISpec")
                continue
            }
            let expectedArities = Set(declarations.flatMap { runtimeABIArityCandidates(for: $0, specs: specs) })
            if !specs.contains(where: { expectedArities.contains($0.parameters.count) }) {
                let arities = specs.map { "\($0.parameters.count)" }.sorted().joined(separator: ", ")
                let expected = expectedArities.map(String.init).sorted().joined(separator: ", ")
                failures.append(
                    "\(linkName) in \(declarations.relativePathList) has Kotlin arity candidates [\(expected)], RuntimeABI arities [\(arities)]"
                )
            }
        }

        #expect(!annotatedDeclarations.isEmpty, "@KsSymbolName coverage should not be empty")
        #expect(
            failures.isEmpty,
            Comment(rawValue: "Bundled @KsSymbolName declarations disagree with RuntimeABISpec: \(failures.joined(separator: "; "))")
        )
    }

    @Test func testBundledKsSymbolNameDeclarationsMatchRuntimeABISignature() throws {
        let annotatedDeclarations = try collectBundledKsSymbolNameDeclarations()
        let runtimeABIByName = Dictionary(grouping: RuntimeABISpec.allFunctions, by: \.name)
        var failures: [String] = []

        for (linkName, declarations) in annotatedDeclarations.groupedByLinkName {
            guard let specs = runtimeABIByName[linkName], !specs.isEmpty else {
                failures.append("\(linkName) in \(declarations.relativePathList) is missing from RuntimeABISpec")
                continue
            }
            // Constructors allocate the instance, so their ABI shape (nullable message
            // pointer, allocation return) does not follow the value-parameter mapping
            // used for functions. Arity is still validated above.
            let functionDeclarations = declarations.filter { !$0.isConstructor }
            guard !functionDeclarations.isEmpty else {
                continue
            }
            let expectedParameterTypeVariants = functionDeclarations.flatMap {
                expectedRuntimeABIParameterTypeVariants(for: $0).map(canonicalHandleTypes)
            }
            let expectedReturnTypes = Set(functionDeclarations.compactMap {
                expectedRuntimeABIReturnType(for: $0).map(canonicalHandleType)
            })
            for spec in specs {
                let actualParameterTypes = spec.parameterTypeStrings
                let coreActual: [String]
                if spec.isThrowing,
                   actualParameterTypes.last == RuntimeABICType.nullableIntptrPointer.rawValue {
                    coreActual = canonicalHandleTypes(actualParameterTypes.dropLast().map { $0 })
                } else {
                    coreActual = canonicalHandleTypes(actualParameterTypes)
                }

                if !expectedParameterTypeVariants.contains(coreActual) {
                    let expected = expectedParameterTypeVariants
                        .map { "[\($0.joined(separator: ", "))]" }
                        .joined(separator: " or ")
                    failures.append(
                        "\(linkName) in \(declarations.relativePathList) has expected ABI parameter types \(expected), but RuntimeABI spec has [\(actualParameterTypes.joined(separator: ", "))]"
                    )
                }
                if !expectedReturnTypes.isEmpty,
                   !expectedReturnTypes.contains(canonicalHandleType(spec.returnTypeString)) {
                    let expected = expectedReturnTypes.sorted().joined(separator: " or ")
                    failures.append(
                        "\(linkName) in \(declarations.relativePathList) has expected ABI return type \(expected), but RuntimeABI spec has \(spec.returnTypeString)"
                    )
                }
            }
        }

        #expect(!annotatedDeclarations.isEmpty, "@KsSymbolName coverage should not be empty")
        #expect(
            failures.isEmpty,
            Comment(rawValue: "Bundled @KsSymbolName declarations disagree with RuntimeABISpec: \(failures.joined(separator: "; "))")
        )
    }

    private var allowedCompilerExternalLinks: Set<String> {
        [
            "kk_for_lowered",
            "kk_int",
            "kk_int_narrow",
            "kk_uint_narrow",
            "kk_lambda_invoke",
            "kk_long",
            "kk_op_add",
            "kk_op_and",
            "kk_op_ishl",
            "kk_op_ishr",
            "kk_op_iushr",
            "kk_op_lshl",
            "kk_op_lshr",
            "kk_op_lushr",
            "kk_op_mul",
            "kk_op_or",
            "kk_op_sub",
            "kk_op_uadd",
            "kk_op_uge",
            "kk_op_ugt",
            "kk_op_ule",
            "kk_op_ult",
            "kk_op_uminus",
            "kk_op_umul",
            "kk_op_uplus",
            "kk_op_usub",
            "kk_program_main",
            "kk_string_length",
            "kk_string_struct_get_length",
            "kk_uint",
            "kk_ulong",
            "kk_unknown_callable",
            "__kk_string_struct_get_length",
        ]
    }

    private func packageRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func collectRuntimeLinkNameLiterals(under roots: [URL]) throws -> Set<String> {
        var names: Set<String> = []
        for root in roots {
            names.formUnion(try collectRuntimeLinkNameLiterals(under: root))
        }
        return names
    }

    private func collectRuntimeLinkNameLiterals(under root: URL) throws -> Set<String> {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var names: Set<String> = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            names.formUnion(runtimeLinkNameLiterals(in: source))
        }
        return names
    }

    fileprivate struct BundledKsSymbolNameDeclaration {
        let linkName: String
        let arity: Int
        let functionTypedParameterCount: Int
        let hasReceiver: Bool
        let isInObjectScope: Bool
        let receiverType: String?
        let valueParameterTypes: [String]
        let valueParameterIsVararg: [Bool]
        let returnType: String?
        let isConstructor: Bool
        let relativePath: String
    }

    private func collectBundledKsSymbolNameDeclarations() throws -> [BundledKsSymbolNameDeclaration] {
        let stdlibRoot = packageRoot().appendingPathComponent("Sources/CompilerCore/Stdlib")
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: stdlibRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var declarations: [BundledKsSymbolNameDeclaration] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "kt" {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let relativePath = fileURL.path.replacingOccurrences(of: stdlibRoot.path + "/", with: "")
            declarations.append(contentsOf: bundledKsSymbolNameDeclarations(in: source, relativePath: relativePath))
        }
        return declarations
    }

    private enum ScopeKind { case classLike, objectLike }

    private struct ScopeEntry {
        let depth: Int
        let kind: ScopeKind
    }

    private func bundledKsSymbolNameDeclarations(
        in source: String,
        relativePath: String
    ) -> [BundledKsSymbolNameDeclaration] {
        var declarations: [BundledKsSymbolNameDeclaration] = []
        var pendingLinkNames: [String] = []
        var pendingScope: ScopeEntry?
        var pendingScopeKind: ScopeKind?
        var braceDepth = 0
        var scopeStack: [ScopeEntry] = []
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        for (index, line) in lines.enumerated() {
            let kind = scopeKind(for: line)
            let delta = braceDelta(in: line)
            if delta < 0, let top = scopeStack.last, top.depth == braceDepth {
                scopeStack.removeLast()
            }
            braceDepth += delta
            if delta > 0 {
                // A class or object header may put its opening brace on the
                // final line of a multiline constructor/supertype list.
                // Carry the declaration kind until that brace is observed.
                if let openedScopeKind = kind ?? pendingScopeKind {
                    scopeStack.append(ScopeEntry(depth: braceDepth, kind: openedScopeKind))
                }
                pendingScopeKind = nil
            } else if let kind {
                pendingScopeKind = kind
            }

            if let linkName = ksSymbolNameArgument(in: line) {
                if pendingLinkNames.isEmpty {
                    pendingScope = scopeStack.last
                }
                pendingLinkNames.append(linkName)
                continue
            }

            // Constructors carry their own lowering (the runtime allocates the
            // object) and have no `fun` header to derive a signature from, so
            // their annotations must not leak onto the next function below.
            if isConstructorDeclaration(line) {
                pendingLinkNames.removeAll()
                pendingScope = nil
                continue
            }

            guard !pendingLinkNames.isEmpty,
                  let functionHeader = functionHeader(startingAt: index, in: lines),
                  let signature = functionSignatureInfo(in: functionHeader)
            else {
                continue
            }
            // A constructor allocates the instance instead of receiving one, so it has no
            // receiver parameter even though it is declared inside a class scope.
            let isConstructor = headerIsConstructor(functionHeader)
            let scopeKind = pendingScope?.kind
            let isInObjectScope = scopeKind == .objectLike
            let hasReceiver = !isConstructor
                && ((scopeKind == .classLike) || functionHeaderHasExtensionReceiver(functionHeader))
            for linkName in pendingLinkNames {
                declarations.append(
                    BundledKsSymbolNameDeclaration(
                        linkName: linkName,
                        arity: signature.valueParameterTypes.count,
                        functionTypedParameterCount: signature.functionTypedParameterCount,
                        hasReceiver: hasReceiver,
                        isInObjectScope: isInObjectScope,
                        receiverType: signature.receiverType,
                        valueParameterTypes: signature.valueParameterTypes,
                        valueParameterIsVararg: signature.valueParameterIsVararg,
                        returnType: signature.returnType,
                        isConstructor: isConstructor,
                        relativePath: relativePath
                    )
                )
            }
            pendingLinkNames.removeAll()
            pendingScope = nil
        }

        return declarations
    }

    private func isConstructorDeclaration(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("//") && !trimmed.hasPrefix("*") else { return false }
        guard let range = trimmed.range(of: "constructor(") else { return false }
        let prefix = trimmed[..<range.lowerBound]
        return prefix.split(whereSeparator: { $0 == " " || $0 == "\t" })
            .allSatisfy { ["public", "internal", "private", "protected"].contains(String($0)) }
    }

    private func ksSymbolNameArgument(in line: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"@KsSymbolName\(\s*(?:name\s*=\s*)?"([^"]+)"\s*\)"#) else {
            return nil
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let valueRange = Range(match.range(at: 1), in: line)
        else {
            return nil
        }
        return String(line[valueRange])
    }

    private func functionHeader(startingAt index: Int, in lines: [String]) -> String? {
        var header = ""
        var parameterParenDepth = 0
        var sawParameterParen = false
        for line in lines[index...] {
            header += " " + line.trimmingCharacters(in: .whitespacesAndNewlines)
            for character in line {
                if character == "(" {
                    parameterParenDepth += 1
                    sawParameterParen = true
                } else if character == ")", sawParameterParen {
                    parameterParenDepth -= 1
                    if parameterParenDepth == 0 {
                        let trimmed = header.trimmingCharacters(in: .whitespaces)
                        if trimmed.contains(" fun ") || trimmed.hasPrefix("fun ") {
                            return header
                        }
                        if headerIsConstructor(header) {
                            return header
                        }
                    }
                }
            }
        }
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        if header.contains(" fun ") || trimmed.hasPrefix("fun ") {
            return header
        }
        return headerIsConstructor(header) ? header : nil
    }

    private func headerIsConstructor(_ header: String) -> Bool {
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        return header.contains(" constructor(") || trimmed.hasPrefix("constructor(")
    }

    private struct FunctionSignatureInfo {
        let receiverType: String?
        let valueParameterTypes: [String]
        let valueParameterIsVararg: [Bool]
        let returnType: String?

        var functionTypedParameterCount: Int {
            valueParameterTypes.filter { $0.contains("->") }.count
        }
    }

    private func functionSignatureInfo(in header: String) -> FunctionSignatureInfo? {
        let suffix: Substring
        if let funRange = header.range(of: "fun ") {
            suffix = header[funRange.upperBound...]
        } else if let constructorRange = header.range(of: "constructor") {
            suffix = header[constructorRange.upperBound...]
        } else {
            return nil
        }
        guard let openParen = suffix.firstIndex(of: "(") else {
            return nil
        }
        let namePrefix = suffix[..<openParen].trimmingCharacters(in: .whitespacesAndNewlines)
        let receiverType = namePrefix.lastIndex(of: ".").map {
            String(namePrefix[..<$0]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var parenDepth = 0
        var closeParen: String.Index?
        var index = openParen
        while index < suffix.endIndex {
            let character = suffix[index]
            if character == "(" {
                parenDepth += 1
            } else if character == ")" {
                parenDepth -= 1
                if parenDepth == 0 {
                    closeParen = index
                    break
                }
            }
            index = suffix.index(after: index)
        }
        guard let closeParen else {
            return nil
        }

        let parameters = suffix[suffix.index(after: openParen)..<closeParen]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var valueParameterTypes: [String] = []
        var valueParameterIsVararg: [Bool] = []
        for parameter in splitTopLevelCommaSeparated(parameters) {
            guard let colon = parameter.firstIndex(of: ":") else {
                continue
            }
            let namePart = parameter[..<colon]
            let isVararg = namePart
                .split(whereSeparator: { $0 == " " || $0 == "\t" })
                .contains("vararg")
            let suffix = parameter[parameter.index(after: colon)...]
            let typePart = suffix.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            valueParameterTypes.append(String(typePart).trimmingCharacters(in: .whitespacesAndNewlines))
            valueParameterIsVararg.append(isVararg)
        }

        let remainder = suffix[suffix.index(after: closeParen)...]
        var returnType: String?
        if let colon = remainder.firstIndex(of: ":") {
            returnType = String(remainder[remainder.index(after: colon)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return FunctionSignatureInfo(
            receiverType: receiverType,
            valueParameterTypes: valueParameterTypes,
            valueParameterIsVararg: valueParameterIsVararg,
            returnType: returnType
        )
    }

    private func splitTopLevelCommaSeparated(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var nestedParens = 0
        var nestedAngles = 0
        for character in text {
            switch character {
            case "(":
                nestedParens += 1
            case ")":
                nestedParens -= 1
            case "<":
                nestedAngles += 1
            case ">" where nestedAngles > 0:
                nestedAngles -= 1
            case "," where nestedParens == 0 && nestedAngles == 0:
                parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current.removeAll()
                continue
            default:
                break
            }
            current.append(character)
        }
        parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return parts.filter { !$0.isEmpty }
    }

    private func functionHeaderHasExtensionReceiver(_ header: String) -> Bool {
        guard let funRange = header.range(of: "fun "),
              let openParen = header[funRange.upperBound...].firstIndex(of: "(")
        else {
            return false
        }
        let declarator = header[funRange.upperBound..<openParen]
        return declarator.contains(".")
    }

    private func runtimeABIArityCandidates(
        for declaration: BundledKsSymbolNameDeclaration,
        specs: [RuntimeABIFunctionSpec]
    ) -> Set<Int> {
        var candidates = Set([declaration.arity])
        var loweredArity = declaration.arity
        if declaration.hasReceiver {
            loweredArity += 1
        }
        loweredArity += declaration.functionTypedParameterCount
        // A `vararg` value parameter lowers to a (packed array pointer, count)
        // pair in the runtime ABI (see CallSupportLowerer's kk_array_of path),
        // so each vararg contributes one extra count parameter.
        loweredArity += declaration.valueParameterIsVararg.filter { $0 }.count
        if specs.contains(where: \.isThrowing) {
            loweredArity += 1
        }
        candidates.insert(loweredArity)
        if declaration.isInObjectScope {
            // Object / companion object members may or may not pass the object
            // receiver across the ABI; include both possibilities.
            candidates.insert(loweredArity + 1)
        }
        if declaration.linkName.hasSuffix("_flat") {
            var flatCount = 0
            if declaration.hasReceiver {
                if let receiverType = declaration.receiverType {
                    flatCount += flatABIParameterCount(for: receiverType)
                } else {
                    // Class / companion / object members have an implicit non-String receiver.
                    flatCount += 1
                }
            }
            flatCount += declaration.valueParameterTypes.reduce(0) { partialResult, type in
                partialResult + flatABIParameterCount(for: type)
            }
            if normalizedKotlinType(declaration.returnType) == "String" {
                flatCount += 3
            }
            if specs.contains(where: \.isThrowing) {
                flatCount += 1
            }
            candidates.insert(flatCount)
            if declaration.isInObjectScope {
                // Object / companion object receiver is a single intptr (non-String).
                candidates.insert(flatCount + 1)
            }
        }
        return candidates
    }

    private func flatABIParameterCount(for type: String?) -> Int {
        normalizedKotlinType(type) == "String" ? 4 : (type == nil ? 0 : 1)
    }

    private func normalizedKotlinType(_ type: String?) -> String {
        guard let type else { return "" }
        return type
            .replacingOccurrences(of: "?", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func braceDelta(in line: String) -> Int {
        var delta = 0
        for character in line {
            if character == "{" {
                delta += 1
            } else if character == "}" {
                delta -= 1
            }
        }
        return delta
    }

    private func scopeKind(for line: String) -> ScopeKind? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("//") && !trimmed.hasPrefix("*") else {
            return nil
        }
        // class / interface / enum class / annotation class / sealed interface / fun interface
        let classLikePattern = #"^\s*(?:(?:public|private|internal|protected|sealed|abstract|data|value|inline|open|final|expect|actual|enum|annotation|fun)\s+)*(?:class|interface)\b"#
        // object / companion object / data object
        let objectPattern = #"^\s*(?:(?:public|private|internal|protected|inline|companion|data)\s+)*(?:companion\s+)?object\b"#
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        if let regex = try? NSRegularExpression(pattern: classLikePattern),
           regex.firstMatch(in: trimmed, range: range) != nil {
            return .classLike
        }
        if let regex = try? NSRegularExpression(pattern: objectPattern),
           regex.firstMatch(in: trimmed, range: range) != nil {
            return .objectLike
        }
        return nil
    }

    private let flatStringParameterTypes: [String] = [
        RuntimeABICType.nullableConstUInt8Pointer.rawValue,
        RuntimeABICType.intptr.rawValue,
        RuntimeABICType.intptr.rawValue,
        RuntimeABICType.intptr.rawValue,
    ]

    private func expectedRuntimeABIParameterTypeVariants(for declaration: BundledKsSymbolNameDeclaration) -> [[String]] {
        let base = expectedRuntimeABIParameterTypes(for: declaration)
        if declaration.isInObjectScope && !declaration.hasReceiver {
            return [
                base,
                [RuntimeABICType.intptr.rawValue] + base,
            ]
        }
        return [base]
    }

    private func expectedRuntimeABIParameterTypes(for declaration: BundledKsSymbolNameDeclaration) -> [String] {
        let isFlat = declaration.linkName.hasSuffix("_flat")
        var types: [String] = []
        if declaration.hasReceiver {
            if let receiverType = declaration.receiverType,
               normalizedKotlinType(receiverType) == "String",
               isFlat {
                types.append(contentsOf: flatStringParameterTypes)
            } else {
                types.append(RuntimeABICType.intptr.rawValue)
            }
        }
        for (index, parameterType) in declaration.valueParameterTypes.enumerated() {
            if index < declaration.valueParameterIsVararg.count,
               declaration.valueParameterIsVararg[index] {
                // vararg -> (packed array pointer, element count)
                types.append(RuntimeABICType.intptr.rawValue)
                types.append(RuntimeABICType.intptr.rawValue)
                continue
            }
            types.append(contentsOf: expectedRuntimeABIParameterTypes(for: parameterType, isFlat: isFlat))
        }
        return types
    }

    private func expectedRuntimeABIParameterTypes(for kotlinType: String, isFlat: Bool) -> [String] {
        let normalized = normalizedKotlinType(kotlinType)
        if isFunctionType(normalized) {
            return [RuntimeABICType.intptr.rawValue, RuntimeABICType.intptr.rawValue]
        }
        if isFlat && normalized == "String" {
            return flatStringParameterTypes
        }
        return [RuntimeABICType.intptr.rawValue]
    }

    private func expectedRuntimeABIReturnType(for declaration: BundledKsSymbolNameDeclaration) -> String? {
        guard let returnType = declaration.returnType else { return nil }
        let isFlat = declaration.linkName.hasSuffix("_flat")
        let normalized = normalizedKotlinType(returnType)
        if isFlat && normalized == "String" {
            return RuntimeABICType.nullableUInt8Pointer.rawValue
        }
        if normalized == "Nothing" {
            return RuntimeABICType.noreturn.rawValue
        }
        return RuntimeABICType.intptr.rawValue
    }

    /// Object handles cross the ABI either as `intptr_t` or as an opaque
    /// pointer; both spellings describe the same single-word value.
    private func canonicalHandleTypes(_ types: [String]) -> [String] {
        types.map(canonicalHandleType)
    }

    private func canonicalHandleType(_ type: String) -> String {
        switch type {
        case RuntimeABICType.opaquePointer.rawValue, RuntimeABICType.nullableOpaquePointer.rawValue:
            RuntimeABICType.intptr.rawValue
        default:
            type
        }
    }

    private func isFunctionType(_ type: String) -> Bool {
        type.contains("->")
    }

    private func runtimeLinkNameLiterals(in source: String) -> Set<String> {
        let patterns = [
            #"interner\.intern\("(kk_[A-Za-z0-9_]+)"\)"#,
            #"(?:==|!=)\s*"(kk_[A-Za-z0-9_]+)""#,
            // Catch kk_ literals stored in variables ending in "Name" (e.g. createCalleeName: "kk_...")
            #"\w+Name\s*:\s*"(kk_[A-Za-z0-9_]+)""#,
        ]
        var names: Set<String> = []
        let sourceRange = NSRange(source.startIndex..<source.endIndex, in: source)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            for match in regex.matches(in: source, range: sourceRange) {
                guard let matchRange = Range(match.range(at: 1), in: source) else {
                    continue
                }
                names.insert(String(source[matchRange]))
            }
        }
        return names
    }
}

private extension [RuntimeABIExternalLinkValidationTests.BundledKsSymbolNameDeclaration] {
    var groupedByLinkName: [(String, Self)] {
        Dictionary(grouping: self, by: \.linkName)
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    var relativePathList: String {
        Set(map(\.relativePath)).sorted().joined(separator: ", ")
    }
}
