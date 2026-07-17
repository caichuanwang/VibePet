import XCTest
@testable import VibePetCore

final class M5InstallerHardeningTests: XCTestCase {
    func testSetupToolSelectorRejectsUnknownValues() {
        XCTAssertEqual(SetupToolSelector.tools(for: nil), [.claudeCode, .codex])
        XCTAssertEqual(SetupToolSelector.tools(for: "all"), [.claudeCode, .codex])
        XCTAssertEqual(SetupToolSelector.tools(for: "claude"), [.claudeCode])
        XCTAssertEqual(SetupToolSelector.tools(for: "claudeCode"), [.claudeCode])
        XCTAssertEqual(SetupToolSelector.tools(for: "codex"), [.codex])
        XCTAssertNil(SetupToolSelector.tools(for: "claudee"))
    }

    func testLegacyToolInstallRecordDecodesUnknownCodexFeatureOwnership() throws {
        let data = Data("""
        {
          "installed": true,
          "activationState": "installedNeedsTrust",
          "settingsPath": "/tmp/config.toml",
          "writtenHooks": ["PermissionRequest"],
          "backupPath": null
        }
        """.utf8)

        let record = try JSONDecoder().decode(ToolInstallRecord.self, from: data)

        XCTAssertEqual(record.codexFeatureStateBeforeInstall, .unknown)
    }

    func testUninstallPreservesPreexistingModernFeature() throws {
        try assertUninstallPreservesFeature(
            initialConfig: "[features]\nhooks = true\n",
            receipt: .enabledModern
        )
    }

    func testUninstallPreservesPreexistingLegacyFeature() throws {
        try assertUninstallPreservesFeature(
            initialConfig: "[features]\ncodex_hooks = true\n",
            receipt: .enabledLegacy
        )
    }

    func testUninstallPreservesFeatureForUnknownOwnership() throws {
        try assertUninstallPreservesFeature(
            initialConfig: "[features]\nhooks = true\n",
            receipt: .unknown
        )
    }

    func testInstallPreservesEnabledLegacyKeyWhenModernKeyIsDisabled() throws {
        let env = try TestEnvironment()
        let writer = env.codexWriter()
        let original = "[features]\ncodex_hooks = true\nhooks = false\n"
        try env.write(Data(original.utf8), to: writer.configURL)

        let receipt = try writer.installWithReceipt(arguments: ["--tool", "codex"])

        XCTAssertEqual(receipt, .codexFeature(.enabledLegacy))
        XCTAssertEqual(try String(contentsOf: writer.configURL, encoding: .utf8), original)
    }

    func testUninstallDisablesFeatureWhenReceiptSaysDisabledAndNoOtherHooksRemain() throws {
        let env = try TestEnvironment()
        let writer = env.codexWriter()
        try writer.install(arguments: ["--tool", "codex"])

        try writer.uninstall(receipt: .codexFeature(.disabled))

        let config = try String(contentsOf: writer.configURL, encoding: .utf8)
        XCTAssertFalse(CodexConfigWriter.featureEnabled(in: config))
    }

    func testUninstallPreservesFeatureWhenForeignHooksRemain() throws {
        let env = try TestEnvironment()
        let writer = env.codexWriter()
        try env.writeForeignCodexHook()
        try writer.install(arguments: ["--tool", "codex"])

        try writer.uninstall(receipt: .codexFeature(.disabled))

        let config = try String(contentsOf: writer.configURL, encoding: .utf8)
        XCTAssertTrue(CodexConfigWriter.featureEnabled(in: config))
        let commands = try env.codexCommands(event: "PreToolUse")
        XCTAssertEqual(commands, ["/usr/local/bin/user-audit"])
    }

    func testRepeatedInstallReconcilesRemovedManagedEntryAndPreservesFirstBackup() throws {
        let env = try TestEnvironment()
        let configURL = env.claudeConfigURL
        try env.write(Data(#"{"model":"claude-user-setting"}"#.utf8), to: configURL)
        let writer = env.claudeWriter()
        let installer = env.installer(writers: [writer])
        let source = try env.makeSourceBinary()
        let first = try installer.install(tool: .claudeCode, hookBinarySource: source)
        let firstBackup = try XCTUnwrap(first.backupPath)

        var root = try env.jsonObject(at: configURL)
        var hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        hooks.removeValue(forKey: "Notification")
        root["hooks"] = hooks
        try env.writeJSON(root, to: configURL)

        let second = try installer.install(tool: .claudeCode, hookBinarySource: source)

        XCTAssertEqual(second.backupPath, firstBackup)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstBackup))
        let repairedRoot = try env.jsonObject(at: configURL)
        let repairedHooks = try XCTUnwrap(repairedRoot["hooks"] as? [String: Any])
        XCTAssertFalse(env.commands(in: repairedHooks, event: "Notification").isEmpty)
    }

    func testExplicitRepairRefreshesLegacyUnknownCodexFeatureOwnership() throws {
        let env = try TestEnvironment()
        let writer = env.codexWriter()
        let installer = env.installer(writers: [writer])
        let source = try env.makeSourceBinary()
        _ = try installer.install(tool: .codex, hookBinarySource: source)
        let store = InstallManifestStore(applicationSupportRoot: env.root)
        var manifest = store.read()
        manifest.tools[ToolKind.codex.rawValue]?.codexFeatureStateBeforeInstall = .unknown
        try store.write(manifest)

        let repaired = try installer.repair(tool: .codex, hookBinarySource: source)

        XCTAssertEqual(repaired.codexFeatureStateBeforeInstall, .enabledModern)
    }

    func testMalformedManifestBlocksInstallWithoutChangingBytesOrBinary() throws {
        let env = try TestEnvironment()
        let store = InstallManifestStore(applicationSupportRoot: env.root)
        let original = Data("{ malformed manifest".utf8)
        try env.write(original, to: store.manifestURL)
        let installer = env.installer(writers: [env.claudeWriter()])

        XCTAssertThrowsError(try installer.install(
            tool: .claudeCode,
            hookBinarySource: env.makeSourceBinary()
        ))
        XCTAssertEqual(try Data(contentsOf: store.manifestURL), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: env.managedBinaryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: env.claudeConfigURL.path))
    }

    func testMalformedClaudeJSONInstallThrowsWithoutChangingBytes() throws {
        let env = try TestEnvironment()
        let original = Data("{ malformed claude json".utf8)
        try env.write(original, to: env.claudeConfigURL)
        let writer = env.claudeWriter()

        XCTAssertThrowsError(try writer.install(arguments: []))
        XCTAssertEqual(try Data(contentsOf: env.claudeConfigURL), original)
    }

    func testMalformedCodexHooksJSONInstallThrowsWithoutChangingBytes() throws {
        let env = try TestEnvironment()
        let writer = env.codexWriter()
        let originalHooks = Data("{ malformed codex json".utf8)
        let originalConfig = Data("[features]\nhooks = false\n".utf8)
        try env.write(originalHooks, to: writer.hooksURL)
        try env.write(originalConfig, to: writer.configURL)

        XCTAssertThrowsError(try writer.install(arguments: ["--tool", "codex"]))
        XCTAssertEqual(try Data(contentsOf: writer.hooksURL), originalHooks)
        XCTAssertEqual(try Data(contentsOf: writer.configURL), originalConfig)
    }

    func testMalformedCodexTOMLInstallThrowsWithoutChangingBytes() throws {
        let env = try TestEnvironment()
        let writer = env.codexWriter()
        let original = Data("[features]\nhooks = false\n[features]\ncodex_hooks = true\n".utf8)
        try env.write(original, to: writer.configURL)

        XCTAssertThrowsError(try writer.install(arguments: ["--tool", "codex"]))
        XCTAssertEqual(try Data(contentsOf: writer.configURL), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: writer.hooksURL.path))
    }

    func testFeaturesArrayOfTablesInstallThrowsWithoutChangingEitherFile() throws {
        let env = try TestEnvironment()
        let writer = env.codexWriter()
        let originalConfig = Data("[[features]]\nname = \"user-entry\"\n".utf8)
        let originalHooks = Data(#"{"hooks":{"PreToolUse":[]}}"#.utf8)
        try env.write(originalConfig, to: writer.configURL)
        try env.write(originalHooks, to: writer.hooksURL)

        XCTAssertThrowsError(try writer.install(arguments: ["--tool", "codex"]))
        XCTAssertEqual(try Data(contentsOf: writer.configURL), originalConfig)
        XCTAssertEqual(try Data(contentsOf: writer.hooksURL), originalHooks)
    }

    func testRootFeaturesNamespaceInstallThrowsWithoutChangingEitherFile() throws {
        for config in [
            "features = { hooks = false }\n",
            "features.hooks = false\n",
            "features = false\n",
        ] {
            let env = try TestEnvironment()
            let writer = env.codexWriter()
            let originalConfig = Data(config.utf8)
            let originalHooks = Data(#"{"hooks":{"PreToolUse":[]}}"#.utf8)
            try env.write(originalConfig, to: writer.configURL)
            try env.write(originalHooks, to: writer.hooksURL)

            XCTAssertThrowsError(try writer.install(arguments: ["--tool", "codex"]))
            XCTAssertEqual(try Data(contentsOf: writer.configURL), originalConfig)
            XCTAssertEqual(try Data(contentsOf: writer.hooksURL), originalHooks)
        }
    }

    func testMalformedContainerOrderAndTableKindConflictPreserveBothFiles() throws {
        for config in [
            "value = [{]}\n",
            "[other]\nvalue = 1\n[[other]]\nvalue = 2\n",
            "[[other]]\nvalue = 1\n[other]\nvalue = 2\n",
        ] {
            let env = try TestEnvironment()
            let writer = env.codexWriter()
            let originalConfig = Data(config.utf8)
            let originalHooks = Data(#"{"hooks":{"PreToolUse":[]}}"#.utf8)
            try env.write(originalConfig, to: writer.configURL)
            try env.write(originalHooks, to: writer.hooksURL)

            XCTAssertThrowsError(try writer.install(arguments: ["--tool", "codex"]))
            XCTAssertEqual(try Data(contentsOf: writer.configURL), originalConfig)
            XCTAssertEqual(try Data(contentsOf: writer.hooksURL), originalHooks)
        }
    }

    func testMalformedCodexTOMLOutsideFeaturesPreservesConfigAndHooks() throws {
        let env = try TestEnvironment()
        let writer = env.codexWriter()
        let originalConfig = Data("model = \"unterminated\n[features]\nhooks = false\n".utf8)
        let originalHooks = Data(#"{"hooks":{"PreToolUse":[]}}"#.utf8)
        try env.write(originalConfig, to: writer.configURL)
        try env.write(originalHooks, to: writer.hooksURL)

        XCTAssertThrowsError(try writer.install(arguments: ["--tool", "codex"]))
        XCTAssertEqual(try Data(contentsOf: writer.configURL), originalConfig)
        XCTAssertEqual(try Data(contentsOf: writer.hooksURL), originalHooks)
    }

    func testMalformedCodexTOMLUninstallPreservesConfigAndHooks() throws {
        let env = try TestEnvironment()
        let writer = env.codexWriter()
        try writer.install(arguments: ["--tool", "codex"])
        let originalConfig = Data("[features]\nhooks = false\n[features] # duplicate\ncodex_hooks = true\n".utf8)
        try env.write(originalConfig, to: writer.configURL)
        let originalHooks = try Data(contentsOf: writer.hooksURL)

        XCTAssertThrowsError(try writer.uninstall(receipt: .codexFeature(.disabled)))
        XCTAssertEqual(try Data(contentsOf: writer.configURL), originalConfig)
        XCTAssertEqual(try Data(contentsOf: writer.hooksURL), originalHooks)
    }

    func testInstallRecognizesCommentedFeaturesHeaderWithoutAppendingDuplicate() throws {
        let env = try TestEnvironment()
        let writer = env.codexWriter()
        let original = "[features] # user comment\nhooks = false\n"
        try env.write(Data(original.utf8), to: writer.configURL)

        try writer.install(arguments: ["--tool", "codex"])

        let updated = try String(contentsOf: writer.configURL, encoding: .utf8)
        XCTAssertEqual(updated.components(separatedBy: "[features]").count - 1, 1)
        XCTAssertTrue(updated.contains("[features] # user comment"))
        XCTAssertTrue(CodexConfigWriter.featureEnabled(in: updated))
    }

    func testInstallRecognizesEquivalentQuotedAndWhitespaceFeaturesHeaders() throws {
        for header in [#"["features"]"#, "['features']", "[ features ]"] {
            let env = try TestEnvironment()
            let writer = env.codexWriter()
            try env.write(Data("\(header)\nhooks = false\n".utf8), to: writer.configURL)

            try writer.install(arguments: ["--tool", "codex"])

            let updated = try String(contentsOf: writer.configURL, encoding: .utf8)
            XCTAssertTrue(updated.contains(header), "preserve original header: \(header)")
            XCTAssertFalse(updated.contains("\n[features]\n"), "must not append a duplicate for \(header)")
            XCTAssertTrue(CodexConfigWriter.featureEnabled(in: updated), "enable existing table: \(header)")
        }
    }

    func testInstallUpdatesEquivalentQuotedFeatureKeysWithoutAddingDuplicate() throws {
        for key in ["\"hooks\"", "'hooks'"] {
            let env = try TestEnvironment()
            let writer = env.codexWriter()
            try env.write(Data("[features]\n\(key) = false\n".utf8), to: writer.configURL)

            try writer.install(arguments: ["--tool", "codex"])

            let updated = try String(contentsOf: writer.configURL, encoding: .utf8)
            XCTAssertTrue(CodexConfigWriter.featureEnabled(in: updated))
            XCTAssertEqual(updated.components(separatedBy: "hooks = true").count - 1, 1)
            XCTAssertFalse(updated.contains("\(key) = false"))
        }
    }

    func testInstallRecognizesCRLFFeaturesHeader() throws {
        let env = try TestEnvironment()
        let writer = env.codexWriter()
        try env.write(Data("[features]\r\nhooks = false\r\n".utf8), to: writer.configURL)

        try writer.install(arguments: ["--tool", "codex"])

        let updated = try String(contentsOf: writer.configURL, encoding: .utf8)
        XCTAssertEqual(updated.components(separatedBy: "[features]").count - 1, 1)
        XCTAssertTrue(CodexConfigWriter.featureEnabled(in: updated))
    }

    func testNestedArrayValueNamedFeaturesIsNotTreatedAsTableHeader() throws {
        let env = try TestEnvironment()
        let writer = env.codexWriter()
        let original = "nested = [\n  [\"features\"]\n]\n"
        try env.write(Data(original.utf8), to: writer.configURL)

        try writer.install(arguments: ["--tool", "codex"])

        let updated = try String(contentsOf: writer.configURL, encoding: .utf8)
        XCTAssertTrue(updated.contains(original))
        XCTAssertTrue(updated.contains("\n[features]\nhooks = true"))
        XCTAssertTrue(CodexConfigWriter.featureEnabled(in: updated))
    }

    func testNestedArrayInsideFeaturesDoesNotEndTableOrDuplicateEnabledKey() throws {
        let env = try TestEnvironment()
        let writer = env.codexWriter()
        let original = "[features]\nnested = [\n  [\"x\"]\n]\nhooks = true\n"
        try env.write(Data(original.utf8), to: writer.configURL)

        try writer.install(arguments: ["--tool", "codex"])

        XCTAssertEqual(try String(contentsOf: writer.configURL, encoding: .utf8), original)
    }

    func testCodexTOMLValidationRejectsUnclosedContainersAndDuplicateTables() {
        XCTAssertFalse(CodexConfigWriter.featureSyntaxIsSafe(in: "paths = [\n\"/tmp\"\n"))
        XCTAssertFalse(CodexConfigWriter.featureSyntaxIsSafe(in: "server = { host = \"local\"\n"))
        XCTAssertFalse(CodexConfigWriter.featureSyntaxIsSafe(in: "[mcp.example]\na = 1\n[mcp.example]\nb = 2\n"))
        XCTAssertFalse(CodexConfigWriter.featureSyntaxIsSafe(
            in: "[features] # first\nhooks = true\n[features] # duplicate\ncodex_hooks = true\n"
        ))
        XCTAssertFalse(CodexConfigWriter.featureSyntaxIsSafe(
            in: "[features]\nhooks = true\n[\"features\"]\ncodex_hooks = true\n"
        ))
        XCTAssertFalse(CodexConfigWriter.featureSyntaxIsSafe(
            in: "[\"invalid\\/key\"]\nvalue = true\n"
        ))
        XCTAssertFalse(CodexConfigWriter.featureSyntaxIsSafe(
            in: "[features]\nnote = \"\\uD800\"\nhooks = false\n"
        ))
        XCTAssertFalse(CodexConfigWriter.featureSyntaxIsSafe(
            in: "[features]\nnote = \"\\uD83D\\uDE00\"\nhooks = false\n"
        ))
        XCTAssertFalse(CodexConfigWriter.featureSyntaxIsSafe(
            in: "[features]\nnote = \"\\U00110000\"\nhooks = false\n"
        ))
        XCTAssertFalse(CodexConfigWriter.featureSyntaxIsSafe(
            in: "[features]\nhooks = false\nhooks = true\n"
        ))
        XCTAssertFalse(CodexConfigWriter.featureSyntaxIsSafe(
            in: "[features]\nhooks.scope = false\n"
        ))
    }

    func testHealthDetectsMalformedManifest() throws {
        let env = try TestEnvironment()
        let writer = env.claudeWriter()
        let store = InstallManifestStore(applicationSupportRoot: env.root)
        try env.write(Data("{ malformed manifest".utf8), to: store.manifestURL)
        let installer = env.installer(writers: [writer])

        let report = try XCTUnwrap(installer.health(tool: .claudeCode))

        XCTAssertTrue(report.issues.contains {
            if case .manifestMalformed(path: store.manifestURL.path) = $0 { return true }
            return false
        })
    }

    func testHealthDetectsExactStaleBinaryPath() throws {
        let env = try TestEnvironment()
        try env.installManagedBinary()
        let staleBinary = env.root.appendingPathComponent("old/VibePetHooks")
        let writer = ClaudeCodeConfigWriter(configURL: env.claudeConfigURL, hookBinaryPath: staleBinary.path)
        try writer.install(arguments: [])

        let report = HookHealthCheck.check(
            tool: .claudeCode,
            writer: writer,
            managedBinaryURL: env.managedBinaryURL,
            recordedInstalled: true
        )

        XCTAssertTrue(report.issues.contains {
            if case .staleCommandPath(recorded: staleBinary.path, configPath: env.claudeConfigURL.path) = $0 {
                return true
            }
            return false
        })
    }

    func testHealthDetectsMissingManagedHookKey() throws {
        let env = try TestEnvironment()
        try env.installManagedBinary()
        let writer = env.claudeWriter()
        try writer.install(arguments: [])
        var root = try env.jsonObject(at: env.claudeConfigURL)
        var hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        hooks.removeValue(forKey: "Notification")
        root["hooks"] = hooks
        try env.writeJSON(root, to: env.claudeConfigURL)

        let report = HookHealthCheck.check(
            tool: .claudeCode,
            writer: writer,
            managedBinaryURL: env.managedBinaryURL,
            recordedInstalled: true
        )

        XCTAssertTrue(report.issues.contains {
            if case .managedHookKeyMissing(key: "Notification", configPath: env.claudeConfigURL.path) = $0 {
                return true
            }
            return false
        })
    }

    func testHealthDetectsCodexCommandMissingToolArgument() throws {
        let env = try TestEnvironment()
        try env.installManagedBinary()
        let writer = env.codexWriter()
        try writer.install(arguments: [])

        let report = HookHealthCheck.check(
            tool: .codex,
            writer: writer,
            managedBinaryURL: env.managedBinaryURL,
            recordedInstalled: true
        )

        XCTAssertTrue(report.issues.contains {
            if case .codexToolArgumentMissing(configPath: writer.hooksURL.path) = $0 { return true }
            return false
        })
    }

    func testHealthDetectsDisabledCodexFeature() throws {
        let env = try TestEnvironment()
        try env.installManagedBinary()
        let writer = env.codexWriter()
        try writer.install(arguments: ["--tool", "codex"])
        try env.write(Data("[features]\nhooks = false\n".utf8), to: writer.configURL)

        let report = HookHealthCheck.check(
            tool: .codex,
            writer: writer,
            managedBinaryURL: env.managedBinaryURL,
            recordedInstalled: true
        )

        XCTAssertTrue(report.issues.contains {
            if case .codexFeatureDisabled(configPath: writer.configURL.path) = $0 { return true }
            return false
        })
    }

    func testHealthCoversExecutableVersionAndManifestDrift() throws {
        let env = try TestEnvironment()
        try env.installManagedBinary()
        let writer = env.claudeWriter()
        try writer.install(arguments: [])
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o644)],
            ofItemAtPath: env.managedBinaryURL.path
        )
        let record = ToolInstallRecord(
            installed: true,
            activationState: .trustedActive,
            settingsPath: "/tmp/wrong-settings.json",
            writtenHooks: ["Stop"],
            backupPath: nil
        )

        let report = HookHealthCheck.check(
            tool: .claudeCode,
            writer: writer,
            managedBinaryURL: env.managedBinaryURL,
            recordedInstalled: true,
            recordedRecord: record,
            recordedBinaryVersion: "0.1",
            expectedBinaryVersion: "0.2"
        )

        XCTAssertTrue(report.issues.contains { if case .binaryNotExecutable = $0 { true } else { false } })
        XCTAssertTrue(report.issues.contains { if case .binaryVersionMismatch = $0 { true } else { false } })
        XCTAssertTrue(report.issues.contains { if case .manifestSettingsPathMismatch = $0 { true } else { false } })
        XCTAssertTrue(report.issues.contains { if case .manifestHookSetMismatch = $0 { true } else { false } })
    }

    func testHealthCheckDoesNotCreateOrModifyManagedPaths() throws {
        let env = try TestEnvironment()
        let installer = env.installer(writers: [env.claudeWriter(), env.codexWriter()])
        let before = try filesystemSnapshot(at: env.root)

        _ = installer.healthReports()

        XCTAssertEqual(try filesystemSnapshot(at: env.root), before)
    }

    func testInvalidExplicitBinaryOverrideDoesNotFallBack() throws {
        let env = try TestEnvironment()
        let invalid = env.root.appendingPathComponent("not-executable")
        try env.write(Data("plain".utf8), to: invalid)
        let adjacent = env.root.appendingPathComponent(HooksBinaryLocator.binaryName)
        try env.makeExecutable(at: adjacent)
        let environment = [HooksBinaryLocator.environmentKey: invalid.path]

        XCTAssertEqual(
            HooksBinaryLocator.locateResult(
                executableDirectory: env.root,
                currentDirectory: env.root,
                applicationSupportRoot: env.root,
                environment: environment
            ),
            .invalidExplicitOverride(invalid.standardizedFileURL)
        )
        XCTAssertNil(HooksBinaryLocator.locate(
            executableDirectory: env.root,
            currentDirectory: env.root,
            applicationSupportRoot: env.root,
            environment: environment
        ))
    }

    func testManagedStableBinaryIsNotAValidSourceCandidate() throws {
        let env = try TestEnvironment()
        try env.installManagedBinary()
        let emptyExecutableDirectory = env.root.appendingPathComponent("empty-executable", isDirectory: true)
        let emptyWorkingDirectory = env.root.appendingPathComponent("empty-working", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyExecutableDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: emptyWorkingDirectory, withIntermediateDirectories: true)

        let result = HooksBinaryLocator.locateResult(
            executableDirectory: emptyExecutableDirectory,
            currentDirectory: emptyWorkingDirectory,
            applicationSupportRoot: env.root,
            environment: [:]
        )

        guard case let .notFound(attempted) = result else {
            return XCTFail("Expected no source candidate, got \(result)")
        }
        XCTAssertFalse(attempted.contains(env.managedBinaryURL.standardizedFileURL))
    }

    private func assertUninstallPreservesFeature(
        initialConfig: String,
        receipt: CodexFeatureStateBeforeInstall
    ) throws {
        let env = try TestEnvironment()
        let writer = env.codexWriter()
        try env.write(Data(initialConfig.utf8), to: writer.configURL)
        try writer.install(arguments: ["--tool", "codex"])

        try writer.uninstall(receipt: .codexFeature(receipt))

        let config = try String(contentsOf: writer.configURL, encoding: .utf8)
        XCTAssertTrue(CodexConfigWriter.featureEnabled(in: config))
    }

    private func filesystemSnapshot(at root: URL) throws -> [String: M5FileSnapshot] {
        try FileManager.default.subpathsOfDirectory(atPath: root.path).reduce(into: [:]) { result, path in
            let url = root.appendingPathComponent(path)
            var isDirectory: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory))
            result[path] = M5FileSnapshot(
                isDirectory: isDirectory.boolValue,
                data: isDirectory.boolValue ? nil : try Data(contentsOf: url)
            )
        }
    }
}

private struct M5FileSnapshot: Equatable {
    let isDirectory: Bool
    let data: Data?
}

private final class TestEnvironment {
    let root: URL

    var managedBinaryURL: URL {
        InstallPaths.hookBinaryURL(applicationSupportRoot: root)
    }

    var claudeConfigURL: URL {
        root.appendingPathComponent("fixtures/claude/settings.json")
    }

    var codexDirectoryURL: URL {
        root.appendingPathComponent("fixtures/codex", isDirectory: true)
    }

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("vp-m5-hardening-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func claudeWriter() -> ClaudeCodeConfigWriter {
        ClaudeCodeConfigWriter(configURL: claudeConfigURL, hookBinaryPath: managedBinaryURL.path)
    }

    func codexWriter() -> CodexConfigWriter {
        CodexConfigWriter(codexDirectory: codexDirectoryURL, hookBinaryPath: managedBinaryURL.path)
    }

    func installer(writers: [any ToolConfigWriter]) -> HookInstaller {
        HookInstaller(applicationSupportRoot: root, writers: writers)
    }

    func makeSourceBinary() throws -> URL {
        let url = root.appendingPathComponent("source/VibePetHooks")
        try makeExecutable(at: url)
        return url
    }

    func installManagedBinary() throws {
        try makeExecutable(at: managedBinaryURL)
    }

    func makeExecutable(at url: URL) throws {
        try write(Data("#!/bin/sh\nexit 0\n".utf8), to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o755)],
            ofItemAtPath: url.path
        )
    }

    func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    func writeJSON(_ object: [String: Any], to url: URL) throws {
        try write(try JSONSerialization.data(withJSONObject: object), to: url)
    }

    func jsonObject(at url: URL) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func commands(in hooks: [String: Any], event: String) -> [String] {
        let groups = (hooks[event] as? [[String: Any]]) ?? []
        return groups.flatMap { group in
            ((group["hooks"] as? [[String: Any]]) ?? []).compactMap { $0["command"] as? String }
        }
    }

    func writeForeignCodexHook() throws {
        let writer = codexWriter()
        let object: [String: Any] = [
            "hooks": [
                "PreToolUse": [[
                    "hooks": [[
                        "type": "command",
                        "command": "/usr/local/bin/user-audit",
                    ]],
                ]],
            ],
        ]
        try writeJSON(object, to: writer.hooksURL)
    }

    func codexCommands(event: String) throws -> [String] {
        let writer = codexWriter()
        guard FileManager.default.fileExists(atPath: writer.hooksURL.path) else { return [] }
        let root = try jsonObject(at: writer.hooksURL)
        let hooks = (root["hooks"] as? [String: Any]) ?? [:]
        return commands(in: hooks, event: event)
    }
}
