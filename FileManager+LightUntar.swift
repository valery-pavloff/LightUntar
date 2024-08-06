//
//  FileManager+LightUntar.swift
//  ALESoftphone
//
//  Created by Valery Pavlov on 06.08.2024.
//  Copyright © 2024 Alcatel-Lucent Enterprise. All rights reserved.
//
// https://github.com/UInt2048/Light-Swift-Untar.git
// BSD 2-Clause License
// Copyright (c) 25/11/2011, Mathieu Hausherr Octo Technology and 06/06/2020, Light-Untar All rights reserved.

import Foundation
enum UntarError: Error, LocalizedError {
    case corruptFile(type: UnicodeScalar)
    case other(String)
    
    public var errorDescription: String? {
        switch self {
        case let .corruptFile(type: type): return "Invalid block type \(type) found"
        case let .other(reason): return "other error \(reason)"
        }
    }
}

public extension FileManager {
    // MARK: - Definitions
    private static var tarBlockSize: UInt64 = 512
    private static var tarTypePosition: UInt64 = 156
    private static var tarNamePosition: UInt64 = 0
    private static var tarNameSize: UInt64 = 100
    private static var tarSizePosition: UInt64 = 124
    private static var tarSizeSize: UInt64 = 12
    private static var tarMaxBlockLoadInMemory: UInt64 = 100

    /// create directory and untar data
    func createFilesAndDirectories(url: URL, tarData: Data) throws {
        try createFilesAndDirectories(path: url.path, tarObject: tarData, size: UInt64(tarData.count))
    }
    
    // MARK: - Private Methods
    private func createFilesAndDirectories(path: String, tarObject: Data, size: UInt64) throws {
        try createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
        var location: UInt64 = 0
        while location < size {
            var blockCount: UInt64 = 1
            
            let type = self.type(object: tarObject, offset: location)
            switch type {
            case "0": // File
                let name = try self.name(object: tarObject, offset: location)
                let filePath = URL(fileURLWithPath: path).appendingPathComponent(name).path
                let size = try self.size(object: tarObject, offset: location)
                if size == 0 {
                    try "".write(toFile: filePath, atomically: true, encoding: .utf8)
                } else {
                    blockCount += (size - 1) / FileManager.tarBlockSize + 1 // size / tarBlockSize rounded up
                    try writeFileData(
                        object: tarObject,
                        location: location + FileManager.tarBlockSize,
                        length: size,
                        path: filePath
                    )
                }
            case "5": // Directory
                let name = try self.name(object: tarObject, offset: location)
                let directoryPath = URL(fileURLWithPath: path).appendingPathComponent(name).path
                try createDirectory(atPath: directoryPath, withIntermediateDirectories: true, attributes: nil)
            case "\0": break // Null block
            case "x": blockCount += 1 // Extra header block
            case "g", "1" ... "7": // Not a file nor directory
                let size = try self.size(object: tarObject, offset: location)
                blockCount += UInt64(ceil(Double(size) / Double(FileManager.tarBlockSize)))
            default: throw UntarError.corruptFile(type: type) // Not a tar type
            }
            location += blockCount * FileManager.tarBlockSize
        }
    }
    
    private func type(object: Data, offset: UInt64) -> UnicodeScalar {
        let typeData = data(object: object, location: offset + FileManager.tarTypePosition, length: 1)
        return UnicodeScalar([UInt8](typeData)[0])
    }
    
    private func name(object: Data, offset: UInt64) throws -> String {
        var nameSize = FileManager.tarNameSize
        for byteNumber in 0...FileManager.tarNameSize {
            let char = String(
                data: data(
                    object: object,
                    location: offset + FileManager.tarNamePosition + byteNumber,
                    length: 1
                ),
                encoding: .ascii
            )
            if char == "\0" {
                nameSize = byteNumber
                break
            }
        }
        let data = data(object: object, location: offset + FileManager.tarNamePosition, length: nameSize)
        guard let string = String(data: data, encoding: .utf8) else { throw UntarError.other("bad name") }
        return string
    }
    
    private func size(object: Data, offset: UInt64) throws -> UInt64 {
        let sizeData = data(
            object: object,
            location: offset + FileManager.tarSizePosition,
            length: FileManager.tarSizeSize
        )
        guard let sizeString = String(data: sizeData, encoding: .ascii) else { throw UntarError.other("bad size") }
        return strtoull(sizeString, nil, 8) // Size is an octal number, convert to decimal
    }
    
    private func writeFileData(object: Data, location: UInt64, length: UInt64, path: String) throws {
        guard createFile(
            atPath: path,
            contents: object.subdata(in: Int(location) ..< Int(location + length)),
            attributes: nil
        ) else {
            throw UntarError.other("create file \(path)")
        }
    }
    
    private func data(object: Data, location: UInt64, length: UInt64) -> Data {
        object.subdata(in: Int(location) ..< Int(location + length))
    }
}
