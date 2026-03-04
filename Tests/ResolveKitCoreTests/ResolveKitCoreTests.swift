import Foundation
import Testing
@testable import ResolveKitCore

@Suite("ResolveKitRegistry")
struct ResolveKitRegistryTests {

    @Test("Register and resolve a function")
    func registerAndResolve() async throws {
        let registry = ResolveKitRegistry()
        try await registry.register(MockFunction.self)
        let resolved = await registry.resolve("mock_fn")
        #expect(resolved != nil)
    }

    @Test("Duplicate registration throws")
    func duplicateThrows() async throws {
        let registry = ResolveKitRegistry()
        try await registry.register(MockFunction.self)
        await #expect(throws: ResolveKitFunctionError.self) {
            try await registry.register(MockFunction.self)
        }
    }

    @Test("Dispatch unknown function throws")
    func dispatchUnknown() async throws {
        let registry = ResolveKitRegistry()
        let context = ResolveKitFunctionContext(sessionID: "s1", requestID: nil)
        await #expect(throws: ResolveKitFunctionError.self) {
            _ = try await registry.dispatch(functionName: "does_not_exist", arguments: [:], context: context)
        }
    }

    @Test("Dispatch known function succeeds")
    func dispatchKnown() async throws {
        let registry = ResolveKitRegistry()
        try await registry.register(MockFunction.self)
        let context = ResolveKitFunctionContext(sessionID: "s1", requestID: nil)
        let result = try await registry.dispatch(
            functionName: "mock_fn",
            arguments: ["value": .string("hello")],
            context: context
        )
        #expect(result == .string("hello"))
    }
}

@Suite("TypeResolver")
struct TypeResolverTests {

    @Test("Bool coercion from number")
    func boolFromNumber() {
        #expect(TypeResolver.coerceBool(.number(1)) == true)
        #expect(TypeResolver.coerceBool(.number(0)) == false)
    }

    @Test("Bool coercion from string")
    func boolFromString() {
        #expect(TypeResolver.coerceBool(.string("true")) == true)
        #expect(TypeResolver.coerceBool(.string("false")) == false)
        #expect(TypeResolver.coerceBool(.string("1")) == true)
    }

    @Test("Int coercion from number")
    func intFromNumber() {
        #expect(TypeResolver.coerceInt(.number(3.0)) == 3)
    }

    @Test("Int coercion from string")
    func intFromString() {
        #expect(TypeResolver.coerceInt(.string("42")) == 42)
    }

    @Test("String coercion from number")
    func stringFromNumber() {
        #expect(TypeResolver.coerceString(.number(7.0)) == "7")
    }
}

@Suite("ResolveKitDefinition")
struct ResolveKitDefinitionTests {

    @Test("Coding round-trip")
    func codingRoundTrip() throws {
        let def = ResolveKitDefinition(
            name: "foo",
            description: "bar",
            parametersSchema: ["type": .string("object"), "properties": .object([:]), "required": .array([])],
            timeoutSeconds: 30
        )
        let data = try JSONEncoder().encode(def)
        let decoded = try JSONDecoder().decode(ResolveKitDefinition.self, from: data)
        #expect(decoded == def)
    }

    @Test("Snake case keys used in JSON")
    func snakeCaseKeys() throws {
        let def = ResolveKitDefinition(name: "n", description: "d", parametersSchema: [:], timeoutSeconds: 10)
        let data = try JSONEncoder().encode(def)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["parameters_schema"] != nil)
        #expect(json?["timeout_seconds"] != nil)
    }
}

@Suite("Binary distribution contract")
struct ResolveKitBinaryDistributionContractTests {

    @Test("Core target is runtime-only and authoring is split out")
    func packageSeparatesAuthoringFromCore() throws {
        let package = try String(contentsOf: sdkRoot.appending(path: "Package.swift"))
        #expect(package.contains(".library(name: \"ResolveKitAuthoring\", targets: [\"ResolveKitAuthoring\"])"))
        #expect(package.contains(".library(name: \"ResolveKitCore\", type: .dynamic, targets: [\"ResolveKitCore\"])"))
        #expect(package.contains(".library(name: \"ResolveKitNetworking\", type: .dynamic, targets: [\"ResolveKitNetworking\"])"))
        #expect(package.contains(".library(name: \"ResolveKitUI\", type: .dynamic, targets: [\"ResolveKitUI\"])"))
        #expect(package.contains(".target(\n            name: \"ResolveKitCore\""))
        #expect(package.contains(".target(\n            name: \"ResolveKitAuthoring\",\n            dependencies: [\n                \"ResolveKitCore\",\n                \"ResolveKitMacros\"\n            ]\n        )"))
        #expect(!package.contains(".target(\n            name: \"ResolveKitCore\",\n            dependencies: [\n                \"ResolveKitMacros\"\n            ]\n        )"))
    }

    @Test("Public wrapper package is binary-only")
    func publicWrapperPackageIsBinaryOnly() throws {
        let wrapperPackageURL = sdkRoot
            .appending(path: "distribution")
            .appending(path: "public-sdk")
            .appending(path: "Package.swift")
        let package = try String(contentsOf: wrapperPackageURL)
        #expect(package.contains(".binaryTarget("))
        #expect(package.contains("ResolveKitCore"))
        #expect(package.contains("ResolveKitNetworking"))
        #expect(package.contains("ResolveKitUI"))
        #expect(!package.contains("ResolveKitMacros"))
        #expect(!package.contains("ResolveKitPlugin"))
        #expect(!package.contains("ResolveKitCodegen"))
    }

    @Test("Release script builds only runtime XCFrameworks")
    func releaseScriptTargetsRuntimeModules() throws {
        let scriptURL = sdkRoot
            .appending(path: "scripts")
            .appending(path: "build-binary-release.sh")
        let script = try String(contentsOf: scriptURL)
        #expect(script.contains("ResolveKitCore"))
        #expect(script.contains("ResolveKitNetworking"))
        #expect(script.contains("ResolveKitUI"))
        #expect(!script.contains("ResolveKitMacros"))
        #expect(!script.contains("ResolveKitPlugin"))
        #expect(!script.contains("ResolveKitCodegen"))
    }

    @Test("Release script supports optional signing and verification")
    func releaseScriptSupportsOptionalSigningAndVerification() throws {
        let scriptURL = sdkRoot
            .appending(path: "scripts")
            .appending(path: "build-binary-release.sh")
        let script = try String(contentsOf: scriptURL)
        #expect(script.contains("SIGNING_IDENTITY"))
        #expect(script.contains("codesign --force --sign"))
        #expect(script.contains("codesign -dv --verbose=4"))
        #expect(script.contains("swift package compute-checksum"))
    }

    @Test("Release script supports local env configuration")
    func releaseScriptSupportsLocalEnvConfiguration() throws {
        let scriptURL = sdkRoot
            .appending(path: "scripts")
            .appending(path: "build-binary-release.sh")
        let gitignoreURL = sdkRoot.appending(path: ".gitignore")
        let script = try String(contentsOf: scriptURL)
        let gitignore = try String(contentsOf: gitignoreURL)

        #expect(script.contains(".env.release"))
        #expect(script.contains("set -a"))
        #expect(script.contains("source"))
        #expect(gitignore.contains(".env.release"))
    }

    @Test("GitHub release script builds then publishes runtime artifacts")
    func githubReleaseScriptBuildsThenPublishesRuntimeArtifacts() throws {
        let scriptURL = sdkRoot
            .appending(path: "scripts")
            .appending(path: "build-and-release-github.sh")
        let script = try String(contentsOf: scriptURL)

        #expect(script.contains("./scripts/build-binary-release.sh"))
        #expect(script.contains("gh release view"))
        #expect(script.contains("gh release upload"))
        #expect(script.contains("--clobber"))
        #expect(script.contains("gh release create"))
        #expect(script.contains("ResolveKitCore.artifactbundle.zip"))
        #expect(script.contains("ResolveKitNetworking.artifactbundle.zip"))
        #expect(script.contains("ResolveKitUI.artifactbundle.zip"))
    }

    @Test("GitHub release script creates and pushes annotated internal tags")
    func githubReleaseScriptCreatesAndPushesAnnotatedInternalTags() throws {
        let scriptURL = sdkRoot
            .appending(path: "scripts")
            .appending(path: "build-and-release-github.sh")
        let script = try String(contentsOf: scriptURL)

        #expect(script.contains("git rev-parse"))
        #expect(script.contains("git tag -a"))
        #expect(script.contains("TAG_REMOTE"))
        #expect(script.contains("refs/tags/${VERSION}"))
        #expect(script.contains("Internal SDK release"))
    }

    private var sdkRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

// MARK: - Mock function for tests

struct MockFunction: AnyResolveKitFunction {
    static let resolveKitName = "mock_fn"
    static let resolveKitDescription = "A mock function"
    static let resolveKitTimeoutSeconds: Int? = nil
    static let resolveKitParametersSchema: JSONObject = [
        "type": .string("object"),
        "properties": .object(["value": .object(["type": .string("string")])]),
        "required": .array([.string("value")])
    ]

    static func invoke(arguments: JSONObject, context: ResolveKitFunctionContext) async throws -> JSONValue {
        guard let v = arguments["value"], case .string(let s) = v else {
            throw ResolveKitFunctionError.invalidArguments("missing value")
        }
        return .string(s)
    }
}
