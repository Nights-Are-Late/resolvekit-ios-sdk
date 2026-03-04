import Foundation

struct Generator {
    let inputDirectory: URL
    let outputFile: URL

    func run() throws {
        let manager = FileManager.default
        let enumerator = manager.enumerator(at: inputDirectory, includingPropertiesForKeys: nil)
        var names: [String] = []

        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            guard let content = try? String(contentsOf: url) else { continue }
            names.append(contentsOf: parseNames(from: content))
        }

        let unique = Array(Set(names)).sorted()
        let list = unique.map { "\($0).self" }.joined(separator: ",\n        ")

        let generated = """
        import ResolveKitCore

        public enum ResolveKitAutoRegistry {
            public static let functions: [any AnyResolveKitFunction.Type] = [
                \(list)
            ]
        }
        """

        try generated.write(to: outputFile, atomically: true, encoding: .utf8)
    }

    private func parseNames(from content: String) -> [String] {
        let pattern = #"@ResolveKit(?:\([^)]*\))?\s*(?:public\s+|internal\s+|open\s+)?struct\s+([A-Za-z_][A-Za-z0-9_]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let range = NSRange(location: 0, length: content.utf16.count)
        return regex.matches(in: content, range: range).compactMap { match in
            guard let range = Range(match.range(at: 1), in: content) else { return nil }
            return String(content[range])
        }
    }
}

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: resolvekit-codegen <input-directory> <output-file>\n", stderr)
    exit(1)
}

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])

try Generator(inputDirectory: input, outputFile: output).run()
