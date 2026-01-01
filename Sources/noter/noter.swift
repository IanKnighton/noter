import ArgumentParser
import Foundation

@main
struct Noter: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "noter",
        abstract: "A note-taking application",
        subcommands: [New.self]
    )
}

extension Noter {
    struct New: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create a new note"
        )
        
        @Option(name: .shortAndLong, help: "Path where notes should be stored")
        var path: String?
        
        func run() throws {
            let notesPath = try getNotesPath()
            let noteFilename = try generateNoteFilename(in: notesPath)
            let noteFullPath = notesPath.appendingPathComponent(noteFilename)
            
            // Create the directory if it doesn't exist
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: notesPath, withIntermediateDirectories: true)
            
            // Create the note file
            let created = fileManager.createFile(atPath: noteFullPath.path, contents: Data())
            
            if created {
                print("Created note: \(noteFullPath.path)")
            } else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        
        private func getNotesPath() throws -> URL {
            // Priority: 1. Command-line argument, 2. Environment variable, 3. Config file, 4. Default
            if let providedPath = path {
                return URL(fileURLWithPath: providedPath)
            }
            
            if let envPath = ProcessInfo.processInfo.environment["NOTER_PATH"] {
                return URL(fileURLWithPath: envPath)
            }
            
            // Try to read from config file in user's home directory
            let homeDir = FileManager.default.homeDirectoryForCurrentUser
            let configPath = homeDir.appendingPathComponent(".noterrc")
            
            if let configData = try? Data(contentsOf: configPath),
               let configString = String(data: configData, encoding: .utf8) {
                let lines = configString.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("path=") {
                        let path = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        return URL(fileURLWithPath: path)
                    }
                }
            }
            
            // Default to ~/notes
            return homeDir.appendingPathComponent("notes")
        }
        
        private func generateNoteFilename(in directory: URL) throws -> String {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd"
            let dateString = dateFormatter.string(from: Date())
            
            let fileManager = FileManager.default
            var version = 0
            
            // Find the next available version number
            while true {
                let filename = "\(dateString).\(version).md"
                let fullPath = directory.appendingPathComponent(filename)
                
                if !fileManager.fileExists(atPath: fullPath.path) {
                    return filename
                }
                
                version += 1
            }
        }
    }
}
