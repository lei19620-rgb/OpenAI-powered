import Combine
import Foundation

@MainActor
final class LocalDictionaryStore: ObservableObject {
    @Published private(set) var packs: [LocalDictionaryPackage] = []
    @Published private(set) var storageError: String?

    private let indexURL: URL
    private let sourceDirectoryURL: URL
    private let builtInPackID = "simple-study-official-dictionary"
    private let builtInIndex: LocalDictionarySQLiteIndex?
    private let builtInIndexError: String?
    private var rawDataByID: [String: Data] = [:]
    private var sourceFileNames: [String: String] = [:]

    init(indexURL: URL? = nil) {
        let resolvedIndexURL = indexURL ?? Self.defaultIndexURL()
        self.indexURL = resolvedIndexURL
        self.sourceDirectoryURL = resolvedIndexURL.deletingPathExtension().appendingPathExtension("packs")
        if let url = Bundle.main.url(forResource: "SimpleStudyDictionary", withExtension: "sqlite") {
            do {
                self.builtInIndex = try LocalDictionarySQLiteIndex(url: url)
                self.builtInIndexError = nil
            } catch {
                self.builtInIndex = nil
                self.builtInIndexError = error.localizedDescription
            }
        } else {
            self.builtInIndex = nil
            self.builtInIndexError = nil
        }
        load()
    }

    var allEntries: [LocalDictionaryEntry] {
        packs.flatMap(\.entries)
    }

    var hasEntries: Bool {
        builtInIndex != nil || packs.contains { !$0.entries.isEmpty }
    }

    var builtInIndexEntryCount: Int? {
        builtInIndex?.package.totalEntryCount
    }

    func lookup(_ query: String) -> LocalDictionaryLookupResult {
        LocalDictionaryLookup.result(for: query, entries: allEntries)
    }

    func lookupAsync(_ query: String) async -> LocalDictionaryLookupResult {
        let customResult = LocalDictionaryLookup.result(for: query, entries: allEntries)
        guard let builtInIndex else { return customResult }

        do {
            let indexedResult = try await builtInIndex.lookup(query)
            return LocalDictionaryLookup.merged(customResult, indexedResult)
        } catch {
            storageError = error.localizedDescription
            return customResult
        }
    }

    func importPackage(data: Data) throws -> LocalDictionaryPackage {
        let package = try LocalDictionaryPackageService.decodeAndValidate(data)
        if package.id == builtInPackID, packs.contains(where: { $0.id == builtInPackID }) {
            throw LocalDictionaryStoreError.builtInPackProtected
        }
        let previous = packs
        let previousRawData = rawDataByID
        let previousFileNames = sourceFileNames
        if let index = packs.firstIndex(where: { $0.id == package.id }) {
            packs[index] = package
        } else {
            packs.append(package)
        }
        rawDataByID[package.id] = data
        sortPacks()

        do {
            try persist()
        } catch {
            packs = previous
            rawDataByID = previousRawData
            sourceFileNames = previousFileNames
            throw error
        }
        return package
    }

    func removePack(id: String) throws {
        if id == builtInPackID {
            throw LocalDictionaryStoreError.builtInPackProtected
        }
        let previous = packs
        let previousRawData = rawDataByID
        let previousFileNames = sourceFileNames
        let removedFileName = sourceFileNames[id]
        packs.removeAll { $0.id == id }
        rawDataByID.removeValue(forKey: id)
        sourceFileNames.removeValue(forKey: id)
        do {
            try persist()
        } catch {
            packs = previous
            rawDataByID = previousRawData
            sourceFileNames = previousFileNames
            throw error
        }
        if let removedFileName {
            try? FileManager.default.removeItem(at: sourceDirectoryURL.appendingPathComponent(removedFileName))
        }
    }

    private func load() {
        var failures: [String] = []

        if let builtInIndexError {
            failures.append("Built-in dictionary: \(builtInIndexError)")
        }

        if FileManager.default.fileExists(atPath: indexURL.path) {
            do {
                let data = try Data(contentsOf: indexURL)
                if let stored = try? JSONCoding.decoder.decode(LocalDictionaryStorePayload.self, from: data),
                   stored.schemaVersion == 2 {
                    for descriptor in stored.packs {
                        do {
                            guard descriptor.fileName == URL(fileURLWithPath: descriptor.fileName).lastPathComponent else {
                                throw LocalDictionaryStoreError.invalidSourceFileName
                            }
                            let sourceURL = sourceDirectoryURL.appendingPathComponent(descriptor.fileName)
                            let rawData = try Data(contentsOf: sourceURL)
                            let package = try LocalDictionaryPackageService.decodeAndValidate(rawData)
                            guard package.id == descriptor.id else {
                                throw LocalDictionaryStoreError.sourceIdentityMismatch
                            }
                            packs.append(package)
                            rawDataByID[package.id] = rawData
                            sourceFileNames[package.id] = descriptor.fileName
                        } catch {
                            failures.append("\(descriptor.title)：\(error.localizedDescription)")
                        }
                    }
                } else if let legacy = try? JSONCoding.decoder.decode(LocalDictionaryLegacyPayload.self, from: data),
                          legacy.schemaVersion == 1 {
                    // Migrate the previous index-only representation. The next
                    // successful write stores the normalized index and a source
                    // file for every user-imported pack.
                    for package in legacy.packs {
                        packs.append(package)
                        rawDataByID[package.id] = (try? LocalDictionaryPackageService.exportData(for: package))
                        sourceFileNames[package.id] = newSourceFileName()
                    }
                    try? persist()
                } else {
                    throw LocalDictionaryStoreError.unsupportedIndexVersion
                }
            } catch {
                failures.append("Index: \(error.localizedDescription)")
            }
        }

        if let builtInIndex,
           !packs.contains(where: { $0.id == builtInIndex.package.id }) {
            packs.insert(builtInIndex.package, at: 0)
        } else if let builtInURL = Bundle.main.url(forResource: "SimpleStudyBuiltInDictionary", withExtension: "json"),
                  let data = try? Data(contentsOf: builtInURL),
                  let builtIn = try? LocalDictionaryPackageService.decodeAndValidate(data),
                  !packs.contains(where: { $0.id == builtIn.id }) {
            packs.insert(builtIn, at: 0)
        }

        sortPacks()
        if !failures.isEmpty {
            storageError = "Dictionary load incomplete: \(failures.joined(separator: "; "))"
        }
    }

    private func persist() throws {
        let previousFileNames = sourceFileNames
        for pack in packs where pack.id != builtInPackID {
            if sourceFileNames[pack.id] == nil {
                sourceFileNames[pack.id] = newSourceFileName()
            }
        }
        let previousFileContents = try captureExistingSourceFiles()
        var directory = indexURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceDirectoryURL, withIntermediateDirectories: true)
        var backupValues = URLResourceValues()
        backupValues.isExcludedFromBackup = true
        try? directory.setResourceValues(backupValues)
        var sourceDirectory = sourceDirectoryURL
        try? sourceDirectory.setResourceValues(backupValues)

        do {
            var descriptors: [LocalDictionaryPackIndex] = []
            for pack in packs where pack.id != builtInPackID {
                guard let fileName = sourceFileNames[pack.id] else {
                    throw LocalDictionaryStoreError.invalidSourceFileName
                }
                let sourceURL = sourceDirectoryURL.appendingPathComponent(fileName)
                let rawData: Data
                if let storedRawData = rawDataByID[pack.id] {
                    rawData = storedRawData
                } else {
                    rawData = try LocalDictionaryPackageService.exportData(for: pack)
                }
                rawDataByID[pack.id] = rawData
                try rawData.write(to: sourceURL, options: .atomic)
                descriptors.append(LocalDictionaryPackIndex(
                    id: pack.id,
                    title: pack.title,
                    language: pack.language,
                    entryCount: pack.totalEntryCount,
                    sourceSummary: pack.sourceSummary,
                    fileName: fileName
                ))
            }

            let payload = LocalDictionaryStorePayload(schemaVersion: 2, packs: descriptors)
            try JSONCoding.encoder.encode(payload).write(to: indexURL, options: .atomic)
            storageError = nil
        } catch {
            restoreSourceFiles(previousFileContents)
            sourceFileNames = previousFileNames
            throw error
        }
    }

    private func sortPacks() {
        packs.sort { lhs, rhs in
            if lhs.id == builtInPackID { return true }
            if rhs.id == builtInPackID { return false }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func newSourceFileName() -> String {
        "pack-\(UUID().uuidString).json"
    }

    private func captureExistingSourceFiles() throws -> [String: Data?] {
        var result: [String: Data?] = [:]
        for fileName in sourceFileNames.values {
            let url = sourceDirectoryURL.appendingPathComponent(fileName)
            result[fileName] = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        }
        return result
    }

    private func restoreSourceFiles(_ files: [String: Data?]) {
        for (fileName, data) in files {
            let url = sourceDirectoryURL.appendingPathComponent(fileName)
            if let data {
                try? data.write(to: url, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func defaultIndexURL() -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return directory
            .appendingPathComponent("SimpleStudy", isDirectory: true)
            .appendingPathComponent("Dictionaries", isDirectory: true)
            .appendingPathComponent("index.json")
    }
}

private struct LocalDictionaryStorePayload: Codable {
    let schemaVersion: Int
    let packs: [LocalDictionaryPackIndex]
}

private struct LocalDictionaryPackIndex: Codable {
    let id: String
    let title: String
    let language: String
    let entryCount: Int
    let sourceSummary: String?
    let fileName: String
}

private struct LocalDictionaryLegacyPayload: Codable {
    let schemaVersion: Int
    let packs: [LocalDictionaryPackage]
}

enum LocalDictionaryStoreError: LocalizedError {
    case builtInPackProtected
    case invalidSourceFileName
    case sourceIdentityMismatch
    case unsupportedIndexVersion

    var errorDescription: String? {
        switch self {
        case .builtInPackProtected: "The built-in dictionary cannot be replaced or deleted."
        case .invalidSourceFileName: "Dictionary index contains an invalid source filename."
        case .sourceIdentityMismatch: "Dictionary source does not match its index."
        case .unsupportedIndexVersion: "Unsupported dictionary index version."
        }
    }
}
