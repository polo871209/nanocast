import Foundation

@main
nonisolated enum FileToolHelper {
    static func main() async {
        guard CommandLine.arguments.count == 2,
            let request = try? JSONDecoder().decode(FileToolRequest.self, from: Data(CommandLine.arguments[1].utf8))
        else { exit(2) }
        do {
            try await FileToolEngine.run(request)
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(1)
        }
    }
}
