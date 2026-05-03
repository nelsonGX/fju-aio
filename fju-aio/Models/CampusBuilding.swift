import Foundation
import CoreLocation

// MARK: - Campus Amenity Model

struct CampusAmenity: Identifiable {
    let id: String
    let name: String
    let category: Category
    let note: String
    let coordinate: CLLocationCoordinate2D

    enum Category {
        case foodCourt
        case convenienceStore

        var title: String {
            switch self {
            case .foodCourt: return "學餐"
            case .convenienceStore: return "便利商店"
            }
        }

        var iconName: String {
            switch self {
            case .foodCourt: return "fork.knife"
            case .convenienceStore: return "bag.fill"
            }
        }
    }

    static let all: [CampusAmenity] = [
        CampusAmenity(
            id: "food-xinyuan",
            name: "心園",
            category: .foodCourt,
            note: "不一定實用的 tips：最大最便宜，在地下室，手機訊號很爛。11:40 後通常差不多滿了，可能要排隊很久。這裡有鬆餅。",
            coordinate: .init(latitude: 25.0368301, longitude: 121.4298168)
        ),
        CampusAmenity(
            id: "food-fuyuan",
            name: "輔園",
            category: .foodCourt,
            note: "不一定實用的 tips：比較高級（貴），但中午也會滿人。有萊爾富可以吃早餐。",
            coordinate: .init(latitude: 25.0344193, longitude: 121.4342800)
        ),
        CampusAmenity(
            id: "food-liyuan",
            name: "理園",
            category: .foodCourt,
            note: "不一定實用的 tips：價位處於中間，有 7-11 之類的，可以來這裡吃早餐。10 點左右以前到 2 點左右以後通常很空，中午 11:50 左右滿人但可能會有單人位子。",
            coordinate: .init(latitude: 25.0354279, longitude: 121.4307475)
        ),
        CampusAmenity(
            id: "store-711-liyuan",
            name: "7-11（理園）",
            category: .convenienceStore,
            note: "鄰近理園座位區，可以買了坐著吃。",
            coordinate: .init(latitude: 25.0354886, longitude: 121.4305893)
        ),
        CampusAmenity(
            id: "store-711-extension",
            name: "7-11（進修部）",
            category: .convenienceStore,
            note: "中午會排很長的隊。",
            coordinate: .init(latitude: 25.0377025, longitude: 121.4299911)
        ),
        CampusAmenity(
            id: "store-hilife",
            name: "萊爾富",
            category: .convenienceStore,
            note: "在輔園裡面。",
            coordinate: .init(latitude: 25.0342905, longitude: 121.4344355)
        ),
        CampusAmenity(
            id: "store-pxmart",
            name: "全聯",
            category: .convenienceStore,
            note: "捷運站進校門口右轉就到了。",
            coordinate: .init(latitude: 25.0328980, longitude: 121.4344892)
        ),
    ]
}

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
        CampusBuilding(code: "LI", name: "文華樓", coordinate: .init(latitude: 25.0364526, longitude: 121.4336470)),
        CampusBuilding(code: "LE", name: "文開樓", coordinate: .init(latitude: 25.0372311, longitude: 121.4338911)),
        CampusBuilding(code: "SH", name: "信義和平男宿", coordinate: .init(latitude: 25.0370245, longitude: 121.4298704)),
        CampusBuilding(code: "SS", name: "仁園 法園", coordinate: .init(latitude: 25.0364867, longitude: 121.4295540)),
        CampusBuilding(code: "NF", name: "秉雅樓", coordinate: .init(latitude: 25.0354594, longitude: 121.4340761)),
        CampusBuilding(code: "FC", name: "輔幼中心", coordinate: .init(latitude: 25.0354765, longitude: 121.4348003)),
        CampusBuilding(code: "TC", name: "朝橒樓", coordinate: .init(latitude: 25.0352529, longitude: 121.4335021)),
        CampusBuilding(code: "LL", name: "文學院圖書館", coordinate: .init(latitude: 25.0362274, longitude: 121.4345187)),
        CampusBuilding(code: "LG", name: "文學院研究所", coordinate: .init(latitude: 25.0365821, longitude: 121.4344972)),
        CampusBuilding(code: "LF", name: "文友樓", coordinate: .init(latitude: 25.0368884, longitude: 121.4336979)),
        CampusBuilding(code: "LP", name: "積健樓", coordinate: .init(latitude: 25.0378313, longitude: 121.4325178)),
        CampusBuilding(code: "LM", name: "利瑪竇大樓", coordinate: .init(latitude: 25.0373258, longitude: 121.4313698)),
        CampusBuilding(code: "SL", name: "羅耀拉大樓", coordinate: .init(latitude: 25.0364315, longitude: 121.4308763)),
        CampusBuilding(code: "JS", name: "濟時樓", coordinate: .init(latitude: 25.0359519, longitude: 121.4301413)),
        CampusBuilding(code: "LW", name: "樹德樓", coordinate: .init(latitude: 25.0363999, longitude: 121.4317131)),
        CampusBuilding(code: "BS", name: "伯達樓", coordinate: .init(latitude: 25.0368641, longitude: 121.4316675)),
        CampusBuilding(code: "LA", name: "外語學院A", coordinate: .init(latitude: 25.0348592, longitude: 121.4324400)),
        CampusBuilding(code: "LB", name: "外語學院B", coordinate: .init(latitude: 25.0350366, longitude: 121.4320832)),
        CampusBuilding(code: "FG", name: "德芳外語大樓", coordinate: .init(latitude: 25.0350901, longitude: 121.4327404)),
        CampusBuilding(code: "LH", name: "理工綜合教室", coordinate: .init(latitude: 25.0344752, longitude: 121.4325795)),
        CampusBuilding(code: "A", name: "耕莘樓", coordinate: .init(latitude: 25.0337510, longitude: 121.4332768)),
    ]

    /// Keywords found in course location strings that map to a building code.
    /// Covers cases where the full Chinese name appears instead of the code.
    private static let keywordMap: [String: String] = [
        "文華樓": "LI",
        "野聲樓": "YP",
        "進修部": "ES",
        "聖言樓": "SF",
        "國璽樓": "MD",
        "文開樓": "LE",
        "信義和平男宿": "SH",
        "仁園": "SS",
        "法園": "SS",
        "秉雅樓": "NF",
        "輔幼中心": "FC",
        "朝橒樓": "TC",
        "文學院圖書館": "LL",
        "文學院研究所": "LG",
        "文友樓": "LF",
        "積健樓": "LP",
        "利瑪竇大樓": "LM",
        "羅耀拉大樓": "SL",
        "濟時樓": "JS",
        "樹德樓": "LW",
        "伯達樓": "BS",
        "外語學院A": "LA",
        "外語學院B": "LB",
        "德芳外語大樓": "FG",
        "理工綜合教室": "LH",
        "耕莘樓": "A",
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
