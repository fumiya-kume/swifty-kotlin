import Foundation

/// Typed representation of a KSwiftK library manifest.json.
/// Replaces untyped `[String: Any]` dictionary access with compile-time safe fields.
///
/// Uses a custom `init(from:)` that wraps each field in `try?` so that a type
/// mismatch in one field (e.g. `"compilerVersion": 123` instead of a string)
/// results in `nil` for that field rather than rejecting the entire manifest.
/// This preserves the per-field-lenient behavior of the old `JSONSerialization`
/// approach, letting `validateManifestSchema` handle each case with appropriate
/// diagnostics.
struct LibraryManifest: Decodable {
    let formatVersion: Int?
    let moduleName: String?
    let kotlinLanguageVersion: String?
    let target: String?
    let compilerVersion: String?
    let metadata: String?
    let inlineKIRDir: String?
    let objects: [String]?

    private enum CodingKeys: String, CodingKey {
        case formatVersion, moduleName, kotlinLanguageVersion, target
        case compilerVersion, metadata, inlineKIRDir, objects
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try? container.decodeIfPresent(Int.self, forKey: .formatVersion)
        moduleName = try? container.decodeIfPresent(String.self, forKey: .moduleName)
        kotlinLanguageVersion = try? container.decodeIfPresent(String.self, forKey: .kotlinLanguageVersion)
        target = try? container.decodeIfPresent(String.self, forKey: .target)
        compilerVersion = try? container.decodeIfPresent(String.self, forKey: .compilerVersion)
        metadata = try? container.decodeIfPresent(String.self, forKey: .metadata)
        inlineKIRDir = try? container.decodeIfPresent(String.self, forKey: .inlineKIRDir)
        objects = try? container.decodeIfPresent([String].self, forKey: .objects)
    }
}

extension DataFlowSemaPhase {
    func discoverLibraryDirectories(searchPaths: [String]) -> [String] {
        let fm = FileManager.default
        var found: Set<String> = []
        for rawPath in searchPaths {
            let path = URL(fileURLWithPath: rawPath).path
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            if path.hasSuffix(".kklib") {
                found.insert(path)
                continue
            }
            guard let entries = try? fm.contentsOfDirectory(atPath: path) else {
                continue
            }
            for entry in entries where entry.hasSuffix(".kklib") {
                found.insert(URL(fileURLWithPath: path).appendingPathComponent(entry).path)
            }
        }
        return found.sorted()
    }

    func resolveLibraryManifestInfo(
        libraryDir: String,
        currentTarget: TargetTriple,
        diagnostics: DiagnosticEngine
    ) -> LibraryManifestInfo {
        let libName = URL(fileURLWithPath: libraryDir).lastPathComponent
        let manifestPath = URL(fileURLWithPath: libraryDir).appendingPathComponent("manifest.json").path

        guard let manifestData = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)) else {
            diagnostics.error(
                "KSWIFTK-LIB-0015",
                "Missing manifest.json in \(libName); library cannot be loaded",
                range: nil
            )
            return LibraryManifestInfo(
                metadataPath: URL(fileURLWithPath: libraryDir).appendingPathComponent("metadata.bin").path,
                inlineKIRDir: nil,
                isValid: false
            )
        }

        let manifest: LibraryManifest
        do {
            manifest = try JSONDecoder().decode(LibraryManifest.self, from: manifestData)
        } catch {
            diagnostics.error(
                "KSWIFTK-LIB-0015",
                "Invalid JSON in \(libName)/manifest.json: \(error.localizedDescription)",
                range: nil
            )
            return LibraryManifestInfo(
                metadataPath: URL(fileURLWithPath: libraryDir).appendingPathComponent("metadata.bin").path,
                inlineKIRDir: nil,
                isValid: false
            )
        }

        var isValid = true

        isValid = validateManifestSchema(
            manifest: manifest,
            libraryDir: libraryDir,
            currentTarget: currentTarget,
            diagnostics: diagnostics
        ) && isValid

        let metadataPath: String
        if let metadataRelativePath = manifest.metadata, !metadataRelativePath.isEmpty {
            metadataPath = URL(fileURLWithPath: libraryDir).appendingPathComponent(metadataRelativePath).path
        } else {
            diagnostics.warning(
                "KSWIFTK-LIB-0016",
                "Missing 'metadata' field in \(libName)/manifest.json; defaulting to metadata.bin",
                range: nil
            )
            metadataPath = URL(fileURLWithPath: libraryDir).appendingPathComponent("metadata.bin").path
        }
        let inlineKIRDir: String? = if let inlineRelativePath = manifest.inlineKIRDir, !inlineRelativePath.isEmpty {
            URL(fileURLWithPath: libraryDir).appendingPathComponent(inlineRelativePath).path
        } else {
            nil
        }

        isValid = validateManifestPaths(
            manifest: manifest,
            libraryDir: libraryDir,
            metadataPath: metadataPath,
            inlineKIRDir: inlineKIRDir,
            diagnostics: diagnostics
        ) && isValid

        return LibraryManifestInfo(metadataPath: metadataPath, inlineKIRDir: inlineKIRDir, isValid: isValid)
    }

    private func validateManifestSchema(
        manifest: LibraryManifest,
        libraryDir: String,
        currentTarget: TargetTriple,
        diagnostics: DiagnosticEngine
    ) -> Bool {
        let libName = URL(fileURLWithPath: libraryDir).lastPathComponent
        var isValid = true

        // formatVersion: required, must be Int == 1
        if let formatVersion = manifest.formatVersion {
            if formatVersion != 1 {
                diagnostics.error(
                    "KSWIFTK-LIB-0010",
                    "Unsupported formatVersion \(formatVersion) in \(libName)/manifest.json (expected 1)",
                    range: nil
                )
                isValid = false
            }
        } else {
            diagnostics.error(
                "KSWIFTK-LIB-0010",
                "Missing or invalid 'formatVersion' in \(libName)/manifest.json",
                range: nil
            )
            isValid = false
        }

        // moduleName: required, must be non-empty String
        if let moduleName = manifest.moduleName {
            if moduleName.isEmpty {
                diagnostics.error(
                    "KSWIFTK-LIB-0011",
                    "Empty 'moduleName' in \(libName)/manifest.json",
                    range: nil
                )
                isValid = false
            }
        } else {
            diagnostics.error(
                "KSWIFTK-LIB-0011",
                "Missing 'moduleName' in \(libName)/manifest.json",
                range: nil
            )
            isValid = false
        }

        // kotlinLanguageVersion: optional but validated when present
        let supportedLanguageVersions: Set = ["2.3.10"]
        if let langVersion = manifest.kotlinLanguageVersion {
            if !supportedLanguageVersions.contains(langVersion) {
                diagnostics.error(
                    "KSWIFTK-LIB-0012",
                    "Unsupported kotlinLanguageVersion '\(langVersion)' in \(libName)/manifest.json (expected one of: \(supportedLanguageVersions.sorted().joined(separator: ", ")))",
                    range: nil
                )
                isValid = false
            }
        } else {
            diagnostics.warning(
                "KSWIFTK-LIB-0012",
                "Missing 'kotlinLanguageVersion' in \(libName)/manifest.json",
                range: nil
            )
        }

        // target: optional but validated for compatibility when present
        if let targetString = manifest.target, !targetString.isEmpty {
            let currentTargetString = "\(currentTarget.arch)-\(currentTarget.vendor)-\(currentTarget.os)"
            if targetString != currentTargetString {
                diagnostics.error(
                    "KSWIFTK-LIB-0013",
                    "Library \(libName) targets '\(targetString)' but current compilation targets '\(currentTargetString)'",
                    range: nil
                )
                isValid = false
            }
        } else {
            diagnostics.warning(
                "KSWIFTK-LIB-0013",
                "Missing 'target' in \(libName)/manifest.json; skipping compatibility check",
                range: nil
            )
        }

        // compilerVersion: informational, warn if empty
        if let compilerVersion = manifest.compilerVersion, compilerVersion.isEmpty {
            diagnostics.warning(
                "KSWIFTK-LIB-0017",
                "Empty 'compilerVersion' in \(libName)/manifest.json",
                range: nil
            )
        }

        return isValid
    }

    private func validateManifestPaths(
        manifest: LibraryManifest,
        libraryDir: String,
        metadataPath: String,
        inlineKIRDir: String?,
        diagnostics: DiagnosticEngine
    ) -> Bool {
        let fm = FileManager.default
        let libName = URL(fileURLWithPath: libraryDir).lastPathComponent
        let libraryDirResolved = URL(fileURLWithPath: libraryDir).standardized.path
        var isValid = true

        // Validate metadata path is within library directory
        let metadataResolved = URL(fileURLWithPath: metadataPath).standardized.path
        if !metadataResolved.hasPrefix(libraryDirResolved + "/"), metadataResolved != libraryDirResolved {
            diagnostics.error(
                "KSWIFTK-LIB-0018",
                "Metadata path '\(metadataPath)' escapes library directory \(libName)",
                range: nil
            )
            isValid = false
        } else if !fm.fileExists(atPath: metadataPath) {
            diagnostics.error(
                "KSWIFTK-LIB-0014",
                "Metadata file not found at '\(metadataPath)' referenced by \(libName)/manifest.json",
                range: nil
            )
            isValid = false
        }

        // Validate objects array paths
        if let objectPaths = manifest.objects {
            for relativePath in objectPaths {
                let fullPath = URL(fileURLWithPath: libraryDir).appendingPathComponent(relativePath).path
                let resolvedObjPath = URL(fileURLWithPath: fullPath).standardized.path
                if !resolvedObjPath.hasPrefix(libraryDirResolved + "/"), resolvedObjPath != libraryDirResolved {
                    diagnostics.error(
                        "KSWIFTK-LIB-0018",
                        "Object path '\(relativePath)' escapes library directory \(libName)",
                        range: nil
                    )
                    isValid = false
                } else if !fm.fileExists(atPath: fullPath) {
                    diagnostics.warning(
                        "KSWIFTK-LIB-0014",
                        "Object file not found at '\(relativePath)' referenced by \(libName)/manifest.json",
                        range: nil
                    )
                }
            }
        }

        // Validate inlineKIRDir path
        if let inlineDir = inlineKIRDir {
            let inlineDirResolved = URL(fileURLWithPath: inlineDir).standardized.path
            if !inlineDirResolved.hasPrefix(libraryDirResolved + "/"), inlineDirResolved != libraryDirResolved {
                diagnostics.error(
                    "KSWIFTK-LIB-0018",
                    "Inline KIR path '\(inlineDir)' escapes library directory \(libName)",
                    range: nil
                )
                isValid = false
            } else {
                var isDirectory: ObjCBool = false
                if !fm.fileExists(atPath: inlineDir, isDirectory: &isDirectory) {
                    diagnostics.warning(
                        "KSWIFTK-LIB-0014",
                        "Inline KIR directory not found at '\(inlineDir)' referenced by \(libName)/manifest.json",
                        range: nil
                    )
                } else if !isDirectory.boolValue {
                    diagnostics.warning(
                        "KSWIFTK-LIB-0014",
                        "Inline KIR path '\(inlineDir)' is not a directory in \(libName)/manifest.json",
                        range: nil
                    )
                }
            }
        }

        return isValid
    }
}
