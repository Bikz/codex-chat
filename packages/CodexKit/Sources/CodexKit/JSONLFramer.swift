import Foundation

enum JSONLFramerError: LocalizedError {
    case bufferOverflow(maxBytes: Int)

    var errorDescription: String? {
        switch self {
        case let .bufferOverflow(maxBytes):
            "JSONL buffer exceeded \(maxBytes) bytes"
        }
    }
}

struct JSONLFramer {
    private(set) var buffered = Data()
    private let maxBufferedBytes: Int

    init(maxBufferedBytes: Int = 4 * 1024 * 1024) {
        self.maxBufferedBytes = maxBufferedBytes
    }

    mutating func append(_ data: Data) throws -> [Data] {
        guard !data.isEmpty else {
            return []
        }

        buffered.append(data)
        if buffered.count > maxBufferedBytes {
            throw JSONLFramerError.bufferOverflow(maxBytes: maxBufferedBytes)
        }

        var frames: [Data] = []
        while let newlineRange = buffered.range(of: Data([0x0A])) {
            let line = buffered[..<newlineRange.lowerBound]
            buffered.removeSubrange(..<newlineRange.upperBound)
            if !line.isEmpty {
                frames.append(Data(line))
            }
        }

        return frames
    }
}
