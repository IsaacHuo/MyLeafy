import Foundation

nonisolated struct WeekendDestination: Identifiable, Hashable, Sendable {
    let id: String
    let cityName: String
    let tagline: String
    let coordinate: CampusCoordinate
    let distanceKilometers: Int
    let travelTimeHours: Double
    let recommendedDays: ClosedRange<Int>
    let bestMonths: [Int]
    let estimatedBudgetYuan: ClosedRange<Int>
    let highlights: [String]

    var travelTimeMinutes: Int {
        Int((travelTimeHours * 60).rounded())
    }

    var tripLengthText: String {
        if recommendedDays.lowerBound == recommendedDays.upperBound {
            return "\(recommendedDays.lowerBound)天"
        }
        return "\(recommendedDays.lowerBound)-\(recommendedDays.upperBound)天"
    }

    var budgetText: String {
        "\(estimatedBudgetYuan.lowerBound)-\(estimatedBudgetYuan.upperBound)元"
    }

    var seasonText: String {
        bestMonths
            .sorted()
            .map(String.init)
            .joined(separator: "/")
    }

    var travelTimeText: String {
        Self.formatMinutes(travelTimeMinutes)
    }

    var highlightRail: [String] {
        let limit = highlights.contains { $0.count > 4 } ? 4 : 5
        return Array(highlights.prefix(limit))
    }

    private static func formatMinutes(_ minutes: Int) -> String {
        let safeMinutes = max(0, minutes)
        let hours = safeMinutes / 60
        let remainder = safeMinutes % 60
        if remainder == 0 {
            return "\(hours)小时"
        }
        return "\(hours)小时\(remainder)分"
    }
}

nonisolated enum WeekendTravelRecommendationEngine {
    static func recommend(
        currentMonth: Int
    ) -> [WeekendDestination] {
        let normalizedMonth = Self.normalizedMonth(currentMonth)

        return destinations
            .sorted { lhs, rhs in
                let lhsScore = score(lhs, month: normalizedMonth)
                let rhsScore = score(rhs, month: normalizedMonth)
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }
                if lhs.distanceKilometers != rhs.distanceKilometers {
                    return lhs.distanceKilometers < rhs.distanceKilometers
                }
                return lhs.cityName < rhs.cityName
            }
    }

    static let destinations: [WeekendDestination] = [
        WeekendDestination(
            id: "tianjin",
            cityName: "天津",
            tagline: "海门东望天连水，千年沽市浪接云。",
            coordinate: CampusCoordinate(latitude: 39.0842, longitude: 117.2009),
            distanceKilometers: 120,
            travelTimeHours: 1.5,
            recommendedDays: 2...3,
            bestMonths: [3, 4, 5, 6, 9, 10, 11],
            estimatedBudgetYuan: 300...700,
            highlights: ["海河", "五大道", "意式风情区"],
        ),
        WeekendDestination(
            id: "cangzhou",
            cityName: "沧州",
            tagline: "千帆夜泊沧州月，一塔晨迎渤海潮。",
            coordinate: CampusCoordinate(latitude: 38.3044, longitude: 116.8387),
            distanceKilometers: 180,
            travelTimeHours: 1.0,
            recommendedDays: 2...3,
            bestMonths: [3, 4, 5, 6, 9, 10, 11],
            estimatedBudgetYuan: 250...550,
            highlights: ["南川老街", "沧州铁狮子", "吴桥杂技大世界"],
        ),
        WeekendDestination(
            id: "shijiazhuang_zhengding",
            cityName: "石家庄（正定古城）",
            tagline: "九楼月照燕南地，四塔风鸣赵北天。",
            coordinate: CampusCoordinate(latitude: 38.1463, longitude: 114.5698),
            distanceKilometers: 280,
            travelTimeHours: 1.5,
            recommendedDays: 2...3,
            bestMonths: [3, 4, 5, 6, 9, 10, 11],
            estimatedBudgetYuan: 300...650,
            highlights: ["正定古城", "隆兴寺", "荣国府"],
        ),
        WeekendDestination(
            id: "tangshan",
            cityName: "唐山",
            tagline: "凤岭新霞衔晓日，南湖旧浪换清波。",
            coordinate: CampusCoordinate(latitude: 39.6307, longitude: 118.1802),
            distanceKilometers: 160,
            travelTimeHours: 1.2,
            recommendedDays: 2...3,
            bestMonths: [4, 5, 6, 9, 10],
            estimatedBudgetYuan: 250...600,
            highlights: ["河头老街", "唐山宴", "清东陵"],
        ),
        WeekendDestination(
            id: "baoding",
            cityName: "保定",
            tagline: "莲池夜月沉珠影，督府秋风动铁衣。",
            coordinate: CampusCoordinate(latitude: 38.874, longitude: 115.464),
            distanceKilometers: 160,
            travelTimeHours: 2.0,
            recommendedDays: 2...3,
            bestMonths: [4, 5, 9, 10],
            estimatedBudgetYuan: 300...650,
            highlights: ["直隶总督署", "古莲花池", "白洋淀"],
        ),
        WeekendDestination(
            id: "zhangjiakou",
            cityName: "张家口",
            tagline: "大境门开迎瀚海，长城垣曲绕寒云。",
            coordinate: CampusCoordinate(latitude: 40.824, longitude: 114.885),
            distanceKilometers: 220,
            travelTimeHours: 2.5,
            recommendedDays: 2...3,
            bestMonths: [1, 2, 6, 7, 8, 9, 10, 12],
            estimatedBudgetYuan: 450...900,
            highlights: ["崇礼", "草原天路", "大境门"],
        ),
        WeekendDestination(
            id: "chengde",
            cityName: "承德",
            tagline: "山庄水色空涵碧，庙宇钟声谷荡幽。",
            coordinate: CampusCoordinate(latitude: 40.957, longitude: 117.93),
            distanceKilometers: 230,
            travelTimeHours: 2.5,
            recommendedDays: 2...3,
            bestMonths: [5, 6, 7, 8, 9, 10],
            estimatedBudgetYuan: 400...800,
            highlights: ["避暑山庄", "普宁寺", "小布达拉宫"],
        ),
        WeekendDestination(
            id: "taiyuan",
            cityName: "太原",
            tagline: "晋祠周柏汾河水，唐碑宋塑西山林。",
            coordinate: CampusCoordinate(latitude: 37.8706, longitude: 112.5489),
            distanceKilometers: 500,
            travelTimeHours: 2.3,
            recommendedDays: 2...3,
            bestMonths: [4, 5, 6, 9, 10, 11],
            estimatedBudgetYuan: 450...850,
            highlights: ["晋祠", "山西博物院", "钟楼街"],
        ),
        WeekendDestination(
            id: "qinhuangdao",
            cityName: "秦皇岛",
            tagline: "秦皇东临遗痕在，魏武挥鞭碣石存。",
            coordinate: CampusCoordinate(latitude: 39.935, longitude: 119.599),
            distanceKilometers: 300,
            travelTimeHours: 3.0,
            recommendedDays: 2...3,
            bestMonths: [6, 7, 8, 9],
            estimatedBudgetYuan: 600...1100,
            highlights: ["北戴河", "山海关", "老龙头"],
        ),
        WeekendDestination(
            id: "qingdao",
            cityName: "青岛",
            tagline: "碧海红楼浮日影，青峦翠屿落鸥声。",
            coordinate: CampusCoordinate(latitude: 36.0671, longitude: 120.3826),
            distanceKilometers: 650,
            travelTimeHours: 4.0,
            recommendedDays: 2...3,
            bestMonths: [5, 6, 7, 8, 9, 10],
            estimatedBudgetYuan: 700...1300,
            highlights: ["栈桥", "八大关", "崂山"],
        ),
        WeekendDestination(
            id: "datong",
            cityName: "大同",
            tagline: "塞上佛光穿壁出，悬寺空檐倚天悬。",
            coordinate: CampusCoordinate(latitude: 40.076, longitude: 113.300),
            distanceKilometers: 340,
            travelTimeHours: 3.5,
            recommendedDays: 3...3,
            bestMonths: [4, 5, 6, 9, 10],
            estimatedBudgetYuan: 600...1000,
            highlights: ["云冈石窟", "华严寺", "古城墙"],
        ),
        WeekendDestination(
            id: "jinan",
            cityName: "济南",
            tagline: "七十二泉珠迸月，半城山色水浮烟。",
            coordinate: CampusCoordinate(latitude: 36.651, longitude: 117.120),
            distanceKilometers: 410,
            travelTimeHours: 3.0,
            recommendedDays: 3...3,
            bestMonths: [3, 4, 5, 6, 9, 10, 11],
            estimatedBudgetYuan: 650...1100,
            highlights: ["趵突泉", "大明湖", "千佛山"],
        ),
        WeekendDestination(
            id: "pingyao",
            cityName: "平遥",
            tagline: "墙楼影压秦时月，市井声喧晋代秋。",
            coordinate: CampusCoordinate(latitude: 37.185, longitude: 112.175),
            distanceKilometers: 600,
            travelTimeHours: 4.5,
            recommendedDays: 3...3,
            bestMonths: [4, 5, 9, 10, 11],
            estimatedBudgetYuan: 700...1200,
            highlights: ["平遥古城", "日升昌", "双林寺"],
        )
    ]

    private static func normalizedMonth(_ month: Int) -> Int {
        guard month >= 1, month <= 12 else {
            return Calendar.current.component(.month, from: Date())
        }
        return month
    }

    private static func score(_ destination: WeekendDestination, month: Int) -> Int {
        let seasonScore = destination.bestMonths.contains(month) ? 100 : 0
        let distanceScore = max(0, 50 - destination.distanceKilometers / 12)
        let budgetScore = max(0, 30 - destination.estimatedBudgetYuan.lowerBound / 50)
        return seasonScore + distanceScore + budgetScore
    }
}
