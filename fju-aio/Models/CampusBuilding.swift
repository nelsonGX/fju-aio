import Foundation
import CoreLocation

// MARK: - Campus Building Model

struct CampusBuilding: Identifiable {
    let id = UUID()
    let code: String
    let name: String
    let coordinate: CLLocationCoordinate2D
}

// MARK: - Campus Building Registry

enum CampusBuildingRegistry {
    static let all: [CampusBuilding] = [
        CampusBuilding(code: "YP", name: "野聲樓", coordinate: .init(latitude: 25.0333476, longitude: 121.4346313)),
        CampusBuilding(code: "ES", name: "進修部", coordinate: .init(latitude: 25.0377292, longitude: 121.4303344)),
        CampusBuilding(code: "SF", name: "聖言樓", coordinate: .init(latitude: 25.0354789, longitude: 121.4316300)),
        CampusBuilding(code: "MD", name: "國璽樓", coordinate: .init(latitude: 25.0386260, longitude: 121.4313403)),
        CampusBuilding(code: "LI", name: "文華樓", coordinate: .init(latitude: 25.0364394, longitude: 121.4313403)),
    ]

    /// Keywords found in course location strings that map to a building code.
    /// Covers cases where the full Chinese name appears instead of the code.
    private static let keywordMap: [String: String] = [
        "文華樓": "LI",
        "野聲樓": "YP",
        "進修部": "ES",
        "聖言樓": "SF",
        "國璽樓": "MD",
    ]

    /// Returns the campus building that best matches a course location string,
    /// e.g. "理圖 SF334", "文華樓 LB302", "SF435".
    static func building(for location: String) -> CampusBuilding? {
        for (keyword, code) in keywordMap {
            if location.contains(keyword) {
                return all.first { $0.code == code }
            }
        }
        return all.first { location.contains($0.code) }
    }
}
