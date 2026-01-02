import ArgumentParser
import Foundation

@main
struct Noter: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "noter",
        abstract: "A note-taking application",
        subcommands: [New.self, Add.self, Combine.self]
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
    
    struct Combine: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Combine notes from a day into a single file"
        )
        
        @Option(name: .shortAndLong, help: "Path where notes should be stored")
        var path: String?
        
        @Flag(name: .long, help: "Keep the original files after combining")
        var keep: Bool = false
        
        @Argument(help: "Specify 'today' to combine only today's notes")
        var filter: String?
        
        func run() throws {
            let notesPath = try getNotesPath(from: path)
            let fileManager = FileManager.default
            
            // Check if directory exists
            guard fileManager.fileExists(atPath: notesPath.path) else {
                print("Notes directory does not exist: \(notesPath.path)")
                return
            }
            
            // Validate filter argument
            if let filter = filter, filter != "today" {
                throw ValidationError("Invalid argument: '\(filter)'. Use 'today' or no argument to combine all notes.")
            }
            
            // Get all markdown files
            let files = try fileManager.contentsOfDirectory(at: notesPath, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            let mdFiles = files.filter { $0.pathExtension == "md" }
            
            guard !mdFiles.isEmpty else {
                print("No notes found in: \(notesPath.path)")
                return
            }
            
            // Parse filenames to group by date: yyyyMMdd.v.md
            var notesByDate: [String: [(version: Int, url: URL)]] = [:]
            
            for file in mdFiles {
                let filename = file.deletingPathExtension().lastPathComponent
                let parts = filename.split(separator: ".")
                
                // Skip files that don't match the expected format
                guard parts.count == 2,
                      let version = Int(parts[1]) else {
                    continue
                }
                
                let dateString = String(parts[0])
                
                // Filter by today if specified
                if filter == "today" {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyyMMdd"
                    let todayString = dateFormatter.string(from: Date())
                    
                    if dateString != todayString {
                        continue
                    }
                }
                
                if notesByDate[dateString] == nil {
                    notesByDate[dateString] = []
                }
                notesByDate[dateString]?.append((version: version, url: file))
            }
            
            guard !notesByDate.isEmpty else {
                if filter == "today" {
                    print("No notes found for today")
                } else {
                    print("No notes found to combine")
                }
                return
            }
            
            // Process each date
            var combinedCount = 0
            for (dateString, notesArray) in notesByDate {
                // Only combine if there are multiple notes for this date
                guard notesArray.count > 1 else {
                    continue
                }
                
                // Sort by version number
                let sortedNotes = notesArray.sorted { $0.version < $1.version }
                
                // Parse date for header
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyyMMdd"
                
                var headerDate = dateString
                if let date = dateFormatter.date(from: dateString) {
                    dateFormatter.dateFormat = "MM-dd-yyyy"
                    headerDate = dateFormatter.string(from: date)
                }
                
                // Build combined content
                var combinedContent = "# \(headerDate)\n\n"
                
                for (index, note) in sortedNotes.enumerated() {
                    if index > 0 {
                        combinedContent += "---\n\n"
                    }
                    
                    // Read the content of this note
                    if let noteContent = try? String(contentsOf: note.url, encoding: .utf8) {
                        combinedContent += noteContent
                        if !noteContent.hasSuffix("\n") {
                            combinedContent += "\n"
                        }
                    }
                }
                
                // Determine the output filename
                let combinedFilename = "\(dateString).0.md"
                let combinedPath = notesPath.appendingPathComponent(combinedFilename)
                
                // Check if we're keeping files - if so, find next available version
                let finalPath: URL
                if keep {
                    // Find the next available version number that doesn't exist
                    var version = 0
                    let maxVersion = 1000
                    var foundPath: URL?
                    
                    while version < maxVersion {
                        let testFilename = "\(dateString).\(version).md"
                        let testPath = notesPath.appendingPathComponent(testFilename)
                        
                        if !fileManager.fileExists(atPath: testPath.path) {
                            foundPath = testPath
                            break
                        }
                        version += 1
                    }
                    
                    guard let path = foundPath else {
                        print("Error: Could not find available version number for \(dateString)")
                        continue
                    }
                    finalPath = path
                } else {
                    finalPath = combinedPath
                }
                
                // Write the combined content
                try combinedContent.write(to: finalPath, atomically: true, encoding: .utf8)
                print("Combined \(sortedNotes.count) notes into: \(finalPath.path)")
                
                // Delete original files if not keeping
                if !keep {
                    for note in sortedNotes {
                        // Don't delete the file we just created
                        if note.url.path != finalPath.path {
                            try fileManager.removeItem(at: note.url)
                        }
                    }
                }
                
                combinedCount += 1
            }
            
            if combinedCount == 0 {
                print("No dates with multiple notes found to combine")
            }
        }
    }
}
