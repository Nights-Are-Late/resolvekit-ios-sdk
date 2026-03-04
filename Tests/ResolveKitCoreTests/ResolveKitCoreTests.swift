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

@Suite("Source release contract")
struct ResolveKitSourceReleaseContractTests {

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

    @Test("README package example references the 0.1.0 source release")
    func readmeReferencesSourceRelease() throws {
        let readme = try String(contentsOf: sdkRoot.appending(path: "README.md"))
        #expect(readme.contains(".package(url: \"https://github.com/Nights-Are-Late/resolvekit-ios-sdk\", from: \"0.1.0\")"))
    }

    @Test("Package remains source-based without binary targets")
    func packageRemainsSourceBased() throws {
        let package = try String(contentsOf: sdkRoot.appending(path: "Package.swift"))
        #expect(!package.contains(".binaryTarget("))
        #expect(package.contains(".library(name: \"ResolveKitCore\", type: .dynamic, targets: [\"ResolveKitCore\"])"))
        #expect(package.contains(".library(name: \"ResolveKitNetworking\", type: .dynamic, targets: [\"ResolveKitNetworking\"])"))
        #expect(package.contains(".library(name: \"ResolveKitUI\", type: .dynamic, targets: [\"ResolveKitUI\"])"))
    }

    @Test("Repository does not ship a binary wrapper package")
    func repositoryOmitsBinaryWrapperPackage() {
        let wrapperPackageURL = sdkRoot
            .appending(path: "distribution")
            .appending(path: "public-sdk")
            .appending(path: "Package.swift")
        #expect(FileManager.default.fileExists(atPath: wrapperPackageURL.path) == false)
    }

    @Test("Repository does not require binary release scripts")
    func repositoryOmitsBinaryReleaseScripts() {
        let binaryReleaseScript = sdkRoot
            .appending(path: "scripts")
            .appending(path: "build-binary-release.sh")
        let githubReleaseScript = sdkRoot
            .appending(path: "scripts")
            .appending(path: "build-and-release-github.sh")

        #expect(FileManager.default.fileExists(atPath: binaryReleaseScript.path) == false)
        #expect(FileManager.default.fileExists(atPath: githubReleaseScript.path) == false)
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
