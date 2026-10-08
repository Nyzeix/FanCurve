import Foundation

struct FanProfileStorage {
    let profiles: [FanProfile]
    let activeProfileID: UUID
}

struct FanProfileStore {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load(defaultProfiles: [FanProfile], legacyCurve: FanCurve?) -> FanProfileStorage {
        if let data = userDefaults.data(forKey: Self.profilesKey),
           let profiles = try? JSONDecoder().decode([FanProfile].self, from: data),
           !profiles.isEmpty {
            let storedID = userDefaults.string(forKey: Self.activeProfileIDKey)
                .flatMap(UUID.init(uuidString:))
            let activeProfileID = storedID.flatMap { id in
                profiles.contains { $0.id == id } ? id : nil
            } ?? profiles[0].id
            return FanProfileStorage(profiles: profiles, activeProfileID: activeProfileID)
        }

        var profiles = defaultProfiles
        let normalProfileIndex = profiles.firstIndex { $0.name == "Normal" } ?? 0
        if let legacyCurve {
            profiles[normalProfileIndex].curve = legacyCurve
        }

        return FanProfileStorage(
            profiles: profiles,
            activeProfileID: profiles[normalProfileIndex].id
        )
    }

    func save(profiles: [FanProfile], activeProfileID: UUID) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        userDefaults.set(data, forKey: Self.profilesKey)
        userDefaults.set(activeProfileID.uuidString, forKey: Self.activeProfileIDKey)
    }

    private static let profilesKey = "FanCurve.profiles"
    private static let activeProfileIDKey = "FanCurve.activeProfileID"
}
