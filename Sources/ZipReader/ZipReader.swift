import CShims
import Glibc
import CMinizip
import Foundation
import Harness
import LoggerAPI
import SwiftGlibc

public struct ZippedFile {
    public let metadata: ZipMetadata
    public let data: Data
}

extension ZippedFile: CustomStringConvertible {

    public var description: String {
        return String(describing: metadata)
    }
}

public struct ZipMetadata {
    public let path: String
    public let size: Int64
    public let compressedSize: Int64
    public let crc32: UInt32
    public let compressionMethod: CompressionMethod

    var ratio: Double {
        return Double(compressedSize) / Double(size)
    }
}

extension ZipMetadata: CustomStringConvertible {

    public var description: String {
        return "\(path): \(size) bytes / \(compressedSize) packed (\(ratio)) CRC32: \(String(crc32, radix: 16, uppercase: false))"
    }
}

public enum CompressionMethod: UInt16 {
    case store = 0
    case deflate = 8
    case bzip2 = 12
    case lzma = 14
    case aes = 99
    case unknown = 1000
}

public class ZipReader {

    private var _zipReader: UnsafeMutableRawPointer?

    var fileCount: Int {
        var count: UInt64 = 0
        let result = mz_zip_get_number_entry(_zipReader, &count)
        if result != MZ_OK {
            Log.error("Minizip error \(result)")
            mz_zip_reader_delete(&_zipReader)
            return -1
        }
        return Int(count)
    }

    public init? (url: URL, inMemory: Bool = false) {

        let result: Int32
        print(url.path)
        mz_zip_reader_create(&_zipReader)
        if inMemory {
            result = mz_zip_reader_open_file_in_memory(_zipReader, url.path)
        } else {
            result = mz_zip_reader_open_file(_zipReader, url.path)
        }
        if result != MZ_OK {
            Log.error("Minizip error \(result)")
            mz_zip_reader_delete(&_zipReader)
            return nil
        }
        if Log.isLogging(.debug) {
            _ = list()
        }
    }

    public func metadata () -> [ZipMetadata] {
        let metadata: [ZipMetadata] = []

        //var result = mz_zip_reader_goto_first_entry(_zipReader)

        return metadata
    }

    public func file(path: String, caseSensitive: Bool = false) -> ZippedFile? {
        var result = mz_zip_reader_locate_entry(_zipReader, path, caseSensitive ? UInt8(0) : UInt8(1))

        if result != MZ_OK {
            if result != MZ_END_OF_LIST {
                Log.error("Minizip error \(result)")
            }
            return nil
        }
        guard let metadata = currentItemMetadata() else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: Int(metadata.size))

        result = mz_zip_reader_entry_open(_zipReader)
        if result != MZ_OK {
            Log.error("mz_zip_reader_entry_open failed: \(result)")
            return nil
        }
        defer {
            mz_zip_reader_entry_close(_zipReader)
        }
        let readCount = mz_zip_reader_entry_read(_zipReader, &buffer, Int32(metadata.size))
        if readCount != metadata.size {
            Log.error("Read \(readCount) bytes from zip, expected \(metadata.size)")
        }
        let crc32 = buffer.crc32
        if metadata.crc32 != crc32 {
            Log.error("Invalid unzipped data, got CRC32 \(crc32), expected \(metadata.crc32)")
            return nil
        }
        return ZippedFile(metadata: metadata, data: Data(buffer))
    }

    private func currentItemMetadata () -> ZipMetadata? {
        var fileInfoPointer: UnsafeMutablePointer<mz_zip_file>? = nil

        let result = mz_zip_reader_entry_get_info(_zipReader, &fileInfoPointer)
        if result != MZ_OK {
            Log.error("mz_zip_reader_entry_get_info failed: \(result)")
            return nil
        }
        guard let info = fileInfoPointer?.pointee else {
            Log.error("Invalid file_info returned from mz_zip_reader_entry_get_info")
            return nil
        }
        let compressionMethod = CompressionMethod(rawValue: info.compression_method) ?? .unknown

        guard let path = String(cString: info.filename, encoding: .utf8) else {
            Log.error("Cannot read path from zip info")
            return nil
        }
        let metadata = ZipMetadata(
            path: path,
            size: info.uncompressed_size,
            compressedSize: info.compressed_size,
            crc32: info.crc,
            compressionMethod: compressionMethod
        )
        return metadata
    }

    private func list () -> Bool {
        return list_zip_archive(_zipReader) == MZ_OK
    }

    deinit {
        mz_zip_reader_delete(&_zipReader)
    }
}
