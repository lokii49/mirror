import SwiftData

enum MirrorModelContainer {
    static let shared: ModelContainer = {
        let schema = Schema([
            Entry.self,
            Insight.self,
            UserProfile.self,
            MoodCheckIn.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .automatic
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
}
