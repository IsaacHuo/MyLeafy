import Foundation

nonisolated struct CampusMapCoordinate: Hashable, Sendable {
    let latitude: Double
    let longitude: Double
}

nonisolated private extension CampusMapCoordinate {
    var mainlandChinaMapCoordinate: CampusMapCoordinate {
        guard isInsideMainlandChina else { return self }

        let latitudeDelta = Self.transformLatitude(x: longitude - 105, y: latitude - 35)
        let longitudeDelta = Self.transformLongitude(x: longitude - 105, y: latitude - 35)
        let radianLatitude = latitude / 180 * Double.pi
        var magic = sin(radianLatitude)
        magic = 1 - Self.eccentricity * magic * magic
        let sqrtMagic = sqrt(magic)
        let adjustedLatitudeDelta = latitudeDelta * 180 / ((Self.earthRadius * (1 - Self.eccentricity)) / (magic * sqrtMagic) * Double.pi)
        let adjustedLongitudeDelta = longitudeDelta * 180 / (Self.earthRadius / sqrtMagic * cos(radianLatitude) * Double.pi)

        return CampusMapCoordinate(
            latitude: latitude + adjustedLatitudeDelta,
            longitude: longitude + adjustedLongitudeDelta
        )
    }

    private var isInsideMainlandChina: Bool {
        (72.004...137.8347).contains(longitude) && (0.8293...55.8271).contains(latitude)
    }

    private static let earthRadius = 6_378_245.0
    private static let eccentricity = 0.00669342162296594323

    private static func transformLatitude(x: Double, y: Double) -> Double {
        var result = -100 + 2 * x + 3 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        result += (20 * sin(6 * x * Double.pi) + 20 * sin(2 * x * Double.pi)) * 2 / 3
        result += (20 * sin(y * Double.pi) + 40 * sin(y / 3 * Double.pi)) * 2 / 3
        result += (160 * sin(y / 12 * Double.pi) + 320 * sin(y * Double.pi / 30)) * 2 / 3
        return result
    }

    private static func transformLongitude(x: Double, y: Double) -> Double {
        var result = 300 + x + 2 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        result += (20 * sin(6 * x * Double.pi) + 20 * sin(2 * x * Double.pi)) * 2 / 3
        result += (20 * sin(x * Double.pi) + 40 * sin(x / 3 * Double.pi)) * 2 / 3
        result += (150 * sin(x / 12 * Double.pi) + 300 * sin(x / 30 * Double.pi)) * 2 / 3
        return result
    }
}

nonisolated enum ClassroomCatalog {
    static let buildings = ["学研A座", "学研B座", "一教", "二教", "三教", "基础楼", "林业楼", "生物楼"]

    static let roomsByBuilding: [String: [String]] = [
        "学研A座": ["0212", "0304", "0306", "0308", "0311", "0313", "0314", "0317", "0318", "0402", "0404", "0406", "0408", "0410", "0413", "0415", "0416", "0419", "0420", "0511", "0513", "0515", "0517", "0519", "0520", "1110", "1112", "1114", "1116", "1118", "1304"],
        "学研B座": ["0204", "0302", "0402", "0404", "0502", "0602"],
        "一教": ["101", "103", "105", "108", "109", "112", "114", "116", "117", "205", "207", "209", "211", "213", "215", "304", "306", "308", "310", "314", "316", "318", "320", "401", "406", "408", "409", "411", "412", "414", "416", "418", "421"],
        "二教": ["101", "102", "103", "104", "105", "106", "107", "108", "109", "110", "201", "202", "203", "204", "205", "206", "207", "208", "209", "301", "302", "303", "304", "305", "306", "307", "308", "309", "310", "401", "402", "403", "404", "405", "406", "407", "408", "409", "501", "502", "503", "504", "505", "506", "507", "508", "509", "510", "510A", "511", "601", "602", "603", "604", "605", "606", "607", "608", "609", "610", "611", "701", "702", "703", "704", "705", "706", "707"],
        "三教": ["102", "105", "107", "108", "201", "203", "205", "301", "302", "304", "310"],
        "基础楼": ["103", "105", "109", "110", "112", "116", "117", "121", "127", "129", "208", "210", "213", "218", "228", "308", "311", "312", "313", "318", "320", "325"],
        "林业楼": ["101", "114", "123", "201", "204", "210", "213"],
        "生物楼": ["101", "104", "108", "110", "114", "115", "118", "204", "206", "209", "210", "214", "311", "312", "315"]
    ]

    private static let layoutCoordinatesByBuilding: [String: CampusMapCoordinate] = [
        "学研A座": CampusMapCoordinate(latitude: 40.00073833995425, longitude: 116.34201854992429),
        "学研B座": CampusMapCoordinate(latitude: 40.000421544987525, longitude: 116.34245761625625),
        "一教": CampusMapCoordinate(latitude: 40.002381159160905, longitude: 116.34207820910797),
        "二教": CampusMapCoordinate(latitude: 40.001545798877736, longitude: 116.3417510420619),
        "三教": CampusMapCoordinate(latitude: 40.004920464276175, longitude: 116.34023499982729),
        "基础楼": CampusMapCoordinate(latitude: 40.00098943355306, longitude: 116.3408810521794),
        "林业楼": CampusMapCoordinate(latitude: 40.00024699042814, longitude: 116.33792579566934),
        "生物楼": CampusMapCoordinate(latitude: 40.00090455800007, longitude: 116.33760942906207)
    ]

    static let mapCenterCoordinate = translatedCoordinate(
        CampusMapCoordinate(latitude: 40.0024, longitude: 116.3408)
    )

    private static let xueyanDashaWGS84Coordinate = CampusMapCoordinate(
        latitude: 40.0003755,
        longitude: 116.3420417
    )

    private static let xueyanDashaLayoutAnchorCoordinate = CampusMapCoordinate(
        latitude: (40.0002448 + 40.0003958) / 2,
        longitude: (116.3432040 + 116.3430690) / 2
    )

    private static let mapAnchorOffset: CampusMapCoordinate = {
        let mapCoordinate = xueyanDashaWGS84Coordinate.mainlandChinaMapCoordinate
        return CampusMapCoordinate(
            latitude: mapCoordinate.latitude - xueyanDashaLayoutAnchorCoordinate.latitude,
            longitude: mapCoordinate.longitude - xueyanDashaLayoutAnchorCoordinate.longitude
        )
    }()

    static func coordinate(for building: String) -> CampusMapCoordinate? {
        let target = ClassroomIdentity(building: building, room: "placeholder")
        guard let coordinate = layoutCoordinatesByBuilding.first(where: { candidate, _ in
            ClassroomIdentity(building: candidate, room: "placeholder") == target
        })?.value else {
            return nil
        }

        return translatedCoordinate(coordinate)
    }

    private static func translatedCoordinate(_ coordinate: CampusMapCoordinate) -> CampusMapCoordinate {
        return CampusMapCoordinate(
            latitude: coordinate.latitude + mapAnchorOffset.latitude,
            longitude: coordinate.longitude + mapAnchorOffset.longitude
        )
    }

    static func floor(for room: String) -> Int? {
        let compact = room
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let digits = compact.prefix { $0.isNumber }
        guard let first = digits.first else { return nil }

        if digits.count >= 4 {
            let floorDigits = digits.prefix(2)
            return Int(String(floorDigits))
        }

        return Int(String(first))
    }
}
