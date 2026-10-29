import Darwin
import Foundation

/// Reads only the URL supplied by the system file picker. No bookmark or copy of
/// the original file is retained. Coordination may download a selected cloud
/// file, so it runs away from the UI executor.
public enum IconPhotoFileReader {
    public static func read(url: URL) async throws -> Data {
        guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        let operation = ReadOperation(url: url)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                operation.start(continuation)
            }
        } onCancel: {
            operation.cancel()
        }
    }

    // An open descriptor, rather than a metadata check followed by an unbounded
    // Data(contentsOf:), keeps both type and size checks valid for this read.
    // Internal size/cancellation seams let tests exercise growth and cancellation
    // with small generated fixtures instead of allocating large source images.
    static func readContents(
        at url: URL,
        maximumBytes: Int = IconPhotoImport.maximumInputBytes,
        checkCancellation: () throws -> Void = {}
    ) throws -> Data {
        try checkCancellation()
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        guard info.st_size >= 0, info.st_size <= maximumBytes else {
            throw IconPhotoImportError.tooManyBytes
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        var data = Data()
        data.reserveCapacity(Int(info.st_size))
        while true {
            try checkCancellation()
            // One extra byte detects growth even when the initial stat was small.
            let count = min(64 * 1_024, maximumBytes - data.count + 1)
            guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else { break }
            guard chunk.count <= maximumBytes - data.count else {
                throw IconPhotoImportError.tooManyBytes
            }
            data.append(chunk)
        }
        try checkCancellation()
        return data
    }

    /// Mutable cross-thread state is protected by `lock`; the coordinator is
    /// created and used on the worker. Only its documented thread-safe cancel()
    /// can run on another thread. A continuation is removed before resumption.
    private final class ReadOperation: @unchecked Sendable {
        private let url: URL
        private let lock = NSLock()
        private var cancelled = false
        private var continuation: CheckedContinuation<Data, any Error>?
        private var coordinator: NSFileCoordinator?

        init(url: URL) { self.url = url }

        func start(_ continuation: CheckedContinuation<Data, any Error>) {
            lock.lock()
            if cancelled {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            self.continuation = continuation
            lock.unlock()
            DispatchQueue.global(qos: .userInitiated).async { self.performRead() }
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let coordinator = self.coordinator
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            coordinator?.cancel()
            continuation?.resume(throwing: CancellationError())
        }

        private func checkCancellation() throws {
            lock.lock()
            let cancelled = cancelled
            lock.unlock()
            if cancelled { throw CancellationError() }
        }

        private func finish(_ result: Result<Data, any Error>) {
            lock.lock()
            let continuation = self.continuation
            self.continuation = nil
            coordinator = nil
            let cancelled = cancelled
            lock.unlock()
            if cancelled { continuation?.resume(throwing: CancellationError()) }
            else { continuation?.resume(with: result) }
        }

        private func performRead() {
            let result = Result<Data, any Error> {
                try checkCancellation()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let coordinator = NSFileCoordinator(filePresenter: nil)
                lock.lock()
                self.coordinator = coordinator
                let cancelled = cancelled
                lock.unlock()
                if cancelled { throw CancellationError() }

                var coordinationError: NSError?
                var readResult: Result<Data, any Error>?
                coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { selectedURL in
                    readResult = Result {
                        try Self.readSelectedContents(at: selectedURL, operation: self)
                    }
                }
                try checkCancellation()
                if let coordinationError { throw coordinationError }
                guard let readResult else { throw CocoaError(.fileReadUnknown) }
                return try readResult.get()
            }
            finish(result)
        }

        private static func readSelectedContents(at url: URL, operation: ReadOperation) throws -> Data {
            guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
            return try IconPhotoFileReader.readContents(at: url, checkCancellation: operation.checkCancellation)
        }
    }
}
