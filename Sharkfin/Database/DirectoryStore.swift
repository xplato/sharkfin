import Foundation
import GRDB
import Observation

@MainActor
@Observable
final class DirectoryStore {
  private(set) var directories: [SharkfinDirectory] = []
  
  let database: AppDatabase
  private var cancellable: AnyDatabaseCancellable?
  
  init(database: AppDatabase) {
    self.database = database
    startObservation()
  }
  
  private func startObservation() {
    let observation = ValueObservation.tracking { db in
      try SharkfinDirectory
        .order(Column("addedAt").desc)
        .fetchAll(db)
    }
    cancellable = observation.start(
      in: database.dbQueue,
      scheduling: .async(onQueue: .main)
    ) { error in
      LoggingService.shared.info(
        "Observation error: \(error)",
        category: "DirectoryStore"
      )
    } onChange: { [weak self] directories in
      MainActor.assumeIsolated {
        self?.directories = directories
      }
    }
  }
}
