import GRDB
import Observation

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
      scheduling: .immediate
    ) { error in
      print("DirectoryStore observation error: \(error)")
    } onChange: { [weak self] directories in
      self?.directories = directories
    }
  }
}
