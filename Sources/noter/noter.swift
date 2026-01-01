import ArgumentParser
import Foundation

@main
struct Noter: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "noter",
        abstract: "A note-taking application",
        subcommands: [New.self, Add.self]
    )
}

// Shared utility functions
func getNotesPath(from providedPath: String?) throws -> URL {
    // Priority: 1. Command-line argument, 2. Environment variable, 3. Config file, 4. Default
    if let providedPath = providedPath {
        return URL(fileURLWithPath: providedPath)
    }
    
    if let envPath = ProcessInfo.processInfo.environment["NOTER_PATH"] {
        return URL(fileURLWithPath: envPath)
    }
    
    // Try to read from config file in user's home directory
    let homeDir = FileManager.default.homeDirectoryForCurrentUser
    let configPath = homeDir.appendingPathComponent(".noterrc")
    let configPrefix = "path="
    
    if let configData = try? Data(contentsOf: configPath),
       let configString = String(data: configData, encoding: .utf8) {
        let lines = configString.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(configPrefix) {
                let path = String(trimmed.dropFirst(configPrefix.count)).trimmingCharacters(in: .whitespaces)
                return URL(fileURLWithPath: path)
            }
        }
    }
    
    // Default to ~/notes
    return homeDir.appendingPathComponent("notes")
}

func generateNoteFilename(in directory: URL) throws -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyyMMdd"
    let dateString = dateFormatter.string(from: Date())
    
    let fileManager = FileManager.default
    var version = 0
    let maxVersion = 1000
    
    // Find the next available version number
    while version < maxVersion {
        let filename = "\(dateString).\(version).md"
        let fullPath = directory.appendingPathComponent(filename)
        
        if !fileManager.fileExists(atPath: fullPath.path) {
            return filename
        }
        
        version += 1
    }
    
    throw CocoaError(.fileWriteFileExists, userInfo: [
        NSLocalizedDescriptionKey: "Maximum number of notes (\(maxVersion)) reached for today"
    ])
}

func formatEntry(content: String) -> String {
    let timeFormatter = DateFormatter()
    timeFormatter.dateFormat = "HH:mm"
    let timeString = timeFormatter.string(from: Date())
    
    return "### \(timeString)\n\n\(content)\n\n"
}

extension Noter {
    struct New: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create a new note"
        )
        
        @Option(name: .shortAndLong, help: "Path where notes should be stored")
        var path: String?
        
        @Argument(help: "Content to add to the new note")
        var content: String?
        
        func run() throws {
            let notesPath = try getNotesPath(from: path)
            let noteFilename = try generateNoteFilename(in: notesPath)
            let noteFullPath = notesPath.appendingPathComponent(noteFilename)
            
            // Create the directory if it doesn't exist
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: notesPath, withIntermediateDirectories: true)
            
            // Prepare initial content if provided
            var initialData = Data()
            if let content = content {
                let entry = formatEntry(content: content)
                initialData = entry.data(using: .utf8) ?? Data()
            }
            
            // Create the note file
            let created = fileManager.createFile(atPath: noteFullPath.path, contents: initialData)
            
            if created {
                print("Created note: \(noteFullPath.path)")
            } else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
    }
    
    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Add content to an existing note"
        )
        
        @Option(name: .shortAndLong, help: "Path where notes should be stored")
        var path: String?
        
        @Option(name: .shortAndLong, help: "Markdown file to append to the note")
        var file: String?
        
        @Argument(help: "Content to add to the note")
        var content: String?
        
        func run() throws {
            // Ensure either content or file is provided, but not both
            if content == nil && file == nil {
                throw ValidationError("Either content or a file must be provided")
            }
            
            if content != nil && file != nil {
                throw ValidationError("Cannot specify both content and a file")
            }
            
            let notesPath = try getNotesPath(from: path)
            
            // Find the most recent note or create a new one
            let noteFullPath: URL
            if let existingNote = try findMostRecentNote(in: notesPath) {
                noteFullPath = existingNote
            } else {
                // No existing note, create a new one
                let fileManager = FileManager.default
                try fileManager.createDirectory(at: notesPath, withIntermediateDirectories: true)
                
                let noteFilename = try generateNoteFilename(in: notesPath)
                noteFullPath = notesPath.appendingPathComponent(noteFilename)
                let created = fileManager.createFile(atPath: noteFullPath.path, contents: Data())
                
                if !created {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
            
            // Determine content to append
            let contentToAppend: String
            if let file = file {
                // Read from file
                let fileURL = URL(fileURLWithPath: file)
                guard fileURL.pathExtension.lowercased() == "md" else {
                    throw ValidationError("Only markdown (.md) files are supported")
                }
                
                guard let fileData = try? Data(contentsOf: fileURL),
                      let fileContent = String(data: fileData, encoding: .utf8) else {
                    throw CocoaError(.fileReadUnknown, userInfo: [
                        NSLocalizedDescriptionKey: "Could not read file: \(file)"
                    ])
                }
                contentToAppend = fileContent
            } else if let textContent = content {
                contentToAppend = textContent
            } else {
                // This should never happen due to validation above, but Swift requires handling
                throw ValidationError("Either content or a file must be provided")
            }
            
            // Append the entry to the note
            let entry = formatEntry(content: contentToAppend)
            
            // Read existing content
            let fileHandle = try FileHandle(forUpdating: noteFullPath)
            defer { try? fileHandle.close() }
            
            // Seek to the end
            if #available(macOS 10.15.4, *) {
                try fileHandle.seekToEnd()
            } else {
                fileHandle.seekToEndOfFile()
            }
            
            // Append new entry
            if let entryData = entry.data(using: .utf8) {
                if #available(macOS 10.15.4, *) {
                    try fileHandle.write(contentsOf: entryData)
                } else {
                    fileHandle.write(entryData)
                }
            }
            
            print("Added entry to: \(noteFullPath.path)")
        }
        
        private func findMostRecentNote(in directory: URL) throws -> URL? {
            let fileManager = FileManager.default
            
            // Check if directory exists
            guard fileManager.fileExists(atPath: directory.path) else {
                return nil
            }
            
            // Get all markdown files in the directory
            let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)
            
            // Filter for .md files
            let mdFiles = files.filter { $0.pathExtension == "md" }
            guard !mdFiles.isEmpty else {
                return nil
            }
            
            // Sort by parsing the filename format: yyyyMMdd.v.md
            let sortedFiles = mdFiles.sorted { file1, file2 in
                let name1 = file1.deletingPathExtension().lastPathComponent
                let name2 = file2.deletingPathExtension().lastPathComponent
                
                let parts1 = name1.split(separator: ".")
                let parts2 = name2.split(separator: ".")
                
                // Compare date first
                if parts1.count >= 1 && parts2.count >= 1 {
                    if parts1[0] != parts2[0] {
                        return parts1[0] > parts2[0]
                    }
                    
                    // If dates are equal, compare version numbers
                    if parts1.count >= 2 && parts2.count >= 2,
                       let v1 = Int(parts1[1]),
                       let v2 = Int(parts2[1]) {
                        return v1 > v2
                    }
                }
                
                // Fallback to string comparison
                return name1 > name2
            }
            
            return sortedFiles.first
        }
    }
}
