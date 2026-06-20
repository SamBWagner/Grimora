import Darwin
import Foundation

enum ProcessLockError: Error, Equatable, CustomStringConvertible {
  case alreadyRunning
  case openFailed(Int32)
  case lockFailed(Int32)

  var description: String {
    switch self {
    case .alreadyRunning:
      "another grimora-data-engine process is already running"
    case .openFailed(let code):
      "could not open process lock: errno \(code)"
    case .lockFailed(let code):
      "could not acquire process lock: errno \(code)"
    }
  }
}

final class ProcessLock {
  private let descriptor: Int32

  init(url: URL) throws {
    descriptor = Darwin.open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else {
      throw ProcessLockError.openFailed(errno)
    }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      let code = errno
      Darwin.close(descriptor)
      if code == EWOULDBLOCK {
        throw ProcessLockError.alreadyRunning
      }
      throw ProcessLockError.lockFailed(code)
    }
  }

  deinit {
    flock(descriptor, LOCK_UN)
    Darwin.close(descriptor)
  }
}
