import Foundation

public func files(withExtension ext: String,
                  in directory: URL) throws -> [URL] {
  let files = try
      FileManager.default.contentsOfDirectory(at: directory,
                                              includingPropertiesForKeys: nil)

  return files.filter { $0.pathExtension == ext }
}

public func siltSourceFiles(in directory: URL) throws -> [URL] {
  return try files(withExtension: "silt", in: directory)
}

public struct SourceFileContents {
  public let url: URL
  public let contents: String
}

public func contentsOfFiles(withExtension ext: String,
                            in directory: URL) throws -> [SourceFileContents] {
  return try files(withExtension: ext, in: directory).map {
    SourceFileContents(url: $0,
                       contents: try String(contentsOf: $0, encoding: .utf8))
  }
}

public func contentsOfSiltSourceFiles(
  in directory: URL) throws -> [SourceFileContents] {
  return try contentsOfFiles(withExtension: "silt", in: directory)
}
