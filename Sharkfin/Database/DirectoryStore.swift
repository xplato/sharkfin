import Foundation
import GRDB
import Observation

@MainActor
@Observable
final class DirectoryStore {
  private(set) var directories: [SharkfinDirectory] = []

  /// Called on the main actor whenever the directories list changes.
  var onDirectoriesChanged: (() -> Void)?

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
      guard let self else { return }
      Task { @MainActor in
        self.directories = directories
        self.onDirectoriesChanged?()
      }
    }
  }
}
