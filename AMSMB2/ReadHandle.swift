//
//  ReadHandle.swift
//  AMSMB2
//
//  All rights reserved.
//

import Foundation

/// A file opened for repeated random-access reads.
///
/// `SMB2Manager.contents(atPath:range:)` opens and closes the file on every call, which costs
/// three round trips per read. A read handle keeps the file open, so each read is a single
/// round trip. This suits callers that read many small ranges of a large file, such as a disk
/// image or a media container.
///
/// The handle belongs to the connection it was opened on. After the share is disconnected or
/// reconnected, reads fail and a new handle must be opened. The file is closed when `close()`
/// is called or the handle is released.
public final class SMB2ReadHandle: @unchecked Sendable {
    private let manager: SMB2Manager
    private let file: SMB2FileHandle

    /// Size of the file in bytes when it was opened.
    public let size: UInt64

    init(manager: SMB2Manager, file: SMB2FileHandle, size: UInt64) {
        self.manager = manager
        self.file = file
        self.size = size
    }

    /// Reads up to `length` bytes starting at `offset`.
    ///
    /// - Note: The returned data is shorter than `length` only when the end of file is reached.
    ///
    /// - Parameters:
    ///   - offset: position of the first byte to read, starting from zero.
    ///   - length: number of bytes to read.
    /// - Returns: a `Data` object which contains the bytes read.
    public func read(offset: UInt64, length: Int) async throws -> Data {
        precondition(length >= 0, "Length must not be negative.")
        let file = file
        return try await manager.perform { _ in
            var result = Data(capacity: length)
            // The server limits the size of a single read, so a large range takes several.
            while result.count < length {
                let count = min(length - result.count, max(file.optimizedReadSize, 1))
                let chunk = try file.read(toAbsoluteOffset: offset + UInt64(result.count), length: count)
                if chunk.isEmpty {
                    break
                }
                result.append(chunk)
            }
            return result
        }
    }

    /// Closes the file. Reading after closing fails.
    public func close() async throws {
        let file = file
        try await manager.perform { _ in
            try file.close()
        }
    }
}
