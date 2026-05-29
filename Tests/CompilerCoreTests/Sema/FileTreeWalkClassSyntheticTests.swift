@testable import CompilerCore
import XCTest

/// STDLIB-IO-TYPE-004: `kotlin.io.FileTreeWalk` class surface.
final class FileTreeWalkClassSyntheticTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            XCTAssertFalse(ctx.diagnostics.hasError, "Expected FileTreeWalk surface to resolve cleanly, got: \(diagnostics)")
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testFileTreeWalkClassIsRegisteredAsSequenceOfFile() throws {
        let (sema, interner) = try makeSema()
        let kotlinIOPkg = ["kotlin", "io"].map { interner.intern($0) }
        let fileTreeWalkFQName = kotlinIOPkg + [interner.intern("FileTreeWalk")]
        let fileTreeWalkSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fileTreeWalkFQName),
            "kotlin.io.FileTreeWalk should be registered"
        )
        let fileTreeWalkInfo = try XCTUnwrap(sema.symbols.symbol(fileTreeWalkSymbol))
        XCTAssertEqual(fileTreeWalkInfo.kind, .class)
        XCTAssertTrue(fileTreeWalkInfo.flags.contains(.synthetic))

        let kotlinIOSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: kotlinIOPkg))
        XCTAssertEqual(sema.symbols.parentSymbol(for: fileTreeWalkSymbol), kotlinIOSymbol)

        let fileTreeWalkType = sema.types.make(.classType(ClassType(
            classSymbol: fileTreeWalkSymbol,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(sema.symbols.propertyType(for: fileTreeWalkSymbol), fileTreeWalkType)

        let sequenceSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("sequences"),
            interner.intern("Sequence"),
        ]))
        let fileSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("File"),
        ]))
        let fileType = sema.types.make(.classType(ClassType(
            classSymbol: fileSymbol,
            args: [],
            nullability: .nonNull
        )))
        let sequenceOfFileArgs: [TypeArg] = [.out(fileType)]

        XCTAssertTrue(sema.symbols.directSupertypes(for: fileTreeWalkSymbol).contains(sequenceSymbol))
        XCTAssertTrue(sema.types.directNominalSupertypes(for: fileTreeWalkSymbol).contains(sequenceSymbol))
        XCTAssertEqual(sema.symbols.supertypeTypeArgs(for: fileTreeWalkSymbol, supertype: sequenceSymbol), sequenceOfFileArgs)
        XCTAssertEqual(sema.types.nominalSupertypeTypeArgs(for: fileTreeWalkSymbol, supertype: sequenceSymbol), sequenceOfFileArgs)
    }

    func testFileTreeWalkConstructorsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let fileTreeWalkSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("io"),
            interner.intern("FileTreeWalk"),
        ]))
        let fileTreeWalkType = sema.types.make(.classType(ClassType(
            classSymbol: fileTreeWalkSymbol,
            args: [],
            nullability: .nonNull
        )))
        let fileSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("File"),
        ]))
        let fileType = sema.types.make(.classType(ClassType(
            classSymbol: fileSymbol,
            args: [],
            nullability: .nonNull
        )))
        let directionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("io"),
            interner.intern("FileWalkDirection"),
        ]))
        let directionType = sema.types.make(.classType(ClassType(
            classSymbol: directionSymbol,
            args: [],
            nullability: .nonNull
        )))
        let constructors = sema.symbols.lookupAll(
            fqName: [
                interner.intern("kotlin"),
                interner.intern("io"),
                interner.intern("FileTreeWalk"),
                interner.intern("<init>"),
            ]
        )

        let defaultConstructor = try XCTUnwrap(constructors.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.parameterTypes == [fileType] && signature.returnType == fileTreeWalkType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: defaultConstructor), "kk_file_tree_walk_new_default")

        let directionConstructor = try XCTUnwrap(constructors.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.parameterTypes == [fileType, directionType] && signature.returnType == fileTreeWalkType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: directionConstructor), "kk_file_tree_walk_new")
    }

    func testFileWalkReturnsFileTreeWalk() throws {
        let (sema, interner) = try makeSema()
        let fileSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("File"),
        ]))
        let fileType = sema.types.make(.classType(ClassType(
            classSymbol: fileSymbol,
            args: [],
            nullability: .nonNull
        )))
        let fileTreeWalkSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("io"),
            interner.intern("FileTreeWalk"),
        ]))
        let fileTreeWalkType = sema.types.make(.classType(ClassType(
            classSymbol: fileTreeWalkSymbol,
            args: [],
            nullability: .nonNull
        )))
        let directionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("io"),
            interner.intern("FileWalkDirection"),
        ]))
        let directionType = sema.types.make(.classType(ClassType(
            classSymbol: directionSymbol,
            args: [],
            nullability: .nonNull
        )))
        let walkFQName = [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("File"),
            interner.intern("walk"),
        ]
        let walkFunctions = sema.symbols.lookupAll(fqName: walkFQName)

        let defaultWalk = try XCTUnwrap(walkFunctions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == fileType
                && signature.parameterTypes == []
                && signature.returnType == fileTreeWalkType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: defaultWalk), "kk_file_walk")

        let directionalWalk = try XCTUnwrap(walkFunctions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == fileType
                && signature.parameterTypes == [directionType]
                && signature.returnType == fileTreeWalkType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: directionalWalk), "kk_file_walk_direction")

        let walkTopDownFunctions = sema.symbols.lookupAll(fqName: [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("File"),
            interner.intern("walkTopDown"),
        ])
        let walkTopDown = try XCTUnwrap(walkTopDownFunctions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == fileType
                && signature.parameterTypes == []
                && signature.returnType == fileTreeWalkType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: walkTopDown), "kk_file_walkTopDown")

        let walkBottomUpFunctions = sema.symbols.lookupAll(fqName: [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("File"),
            interner.intern("walkBottomUp"),
        ])
        let walkBottomUp = try XCTUnwrap(walkBottomUpFunctions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == fileType
                && signature.parameterTypes == []
                && signature.returnType == fileTreeWalkType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: walkBottomUp), "kk_file_walkBottomUp")
    }

    func testFileTreeWalkResolvesInSource() throws {
        _ = try makeSema(source: """
        import java.io.File
        import kotlin.io.FileTreeWalk
        import kotlin.io.FileWalkDirection
        import kotlin.sequences.Sequence

        fun defaultWalk(file: File): FileTreeWalk = file.walk()
        fun bottomUpWalk(file: File): FileTreeWalk = file.walk(FileWalkDirection.BOTTOM_UP)
        fun topDownShortcut(file: File): FileTreeWalk = file.walkTopDown()
        fun bottomUpShortcut(file: File): FileTreeWalk = file.walkBottomUp()
        fun walkAsSequence(file: File): Sequence<File> = file.walk()
        fun constructDefault(file: File): FileTreeWalk = FileTreeWalk(file)
        fun constructBottomUp(file: File): FileTreeWalk = FileTreeWalk(file, FileWalkDirection.BOTTOM_UP)
        """)
    }
}
