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
    let suggestedPace: String

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
            tagline: "海河夜景、小吃和近代建筑，适合说走就走。",
            coordinate: CampusCoordinate(latitude: 39.0842, longitude: 117.2009),
            distanceKilometers: 120,
            travelTimeHours: 1.5,
            recommendedDays: 2...3,
            bestMonths: [3, 4, 5, 6, 9, 10, 11],
            estimatedBudgetYuan: 300...700,
            highlights: ["海河", "五大道", "意式风情区"],
            suggestedPace: "海河夜景和五大道适合轻松串行，周末慢慢走很舒服。"
        ),
        WeekendDestination(
            id: "cangzhou",
            cityName: "沧州",
            tagline: "老街、铁狮子和杂技，离北京很近，适合轻量周末。",
            coordinate: CampusCoordinate(latitude: 38.3044, longitude: 116.8387),
            distanceKilometers: 180,
            travelTimeHours: 1.0,
            recommendedDays: 2...3,
            bestMonths: [3, 4, 5, 6, 9, 10, 11],
            estimatedBudgetYuan: 250...550,
            highlights: ["南川老街", "沧州铁狮子", "吴桥杂技大世界"],
            suggestedPace: "老街、铁狮子和杂技园区就足够撑起一个轻周末。"
        ),
        WeekendDestination(
            id: "shijiazhuang_zhengding",
            cityName: "石家庄（正定）",
            tagline: "古城、隆兴寺和南城门，把历史和小吃一起打包。",
            coordinate: CampusCoordinate(latitude: 38.1463, longitude: 114.5698),
            distanceKilometers: 280,
            travelTimeHours: 1.5,
            recommendedDays: 2...3,
            bestMonths: [3, 4, 5, 6, 9, 10, 11],
            estimatedBudgetYuan: 300...650,
            highlights: ["正定古城", "隆兴寺", "荣国府"],
            suggestedPace: "正定古城、隆兴寺和南城门连着走最顺。"
        ),
        WeekendDestination(
            id: "tangshan",
            cityName: "唐山",
            tagline: "海港、老街和工业遗存，离北京很近，节奏轻松。",
            coordinate: CampusCoordinate(latitude: 39.6307, longitude: 118.1802),
            distanceKilometers: 160,
            travelTimeHours: 1.2,
            recommendedDays: 2...3,
            bestMonths: [4, 5, 6, 9, 10],
            estimatedBudgetYuan: 250...600,
            highlights: ["河头老街", "唐山宴", "清东陵"],
            suggestedPace: "唐山宴、河头老街和清东陵可以串成一条线。"
        ),
        WeekendDestination(
            id: "baoding",
            cityName: "保定",
            tagline: "古城、直隶总督署和驴火，把预算压得很舒服。",
            coordinate: CampusCoordinate(latitude: 38.874, longitude: 115.464),
            distanceKilometers: 160,
            travelTimeHours: 2.0,
            recommendedDays: 2...3,
            bestMonths: [4, 5, 9, 10],
            estimatedBudgetYuan: 300...650,
            highlights: ["直隶总督署", "古莲花池", "白洋淀"],
            suggestedPace: "古城、园林和白洋淀可以按兴趣拆开看，节奏从容。"
        ),
        WeekendDestination(
            id: "zhangjiakou",
            cityName: "张家口",
            tagline: "草原风、崇礼山地和冬季雪场，换个空气很明显。",
            coordinate: CampusCoordinate(latitude: 40.824, longitude: 114.885),
            distanceKilometers: 220,
            travelTimeHours: 2.5,
            recommendedDays: 2...3,
            bestMonths: [1, 2, 6, 7, 8, 9, 10, 12],
            estimatedBudgetYuan: 450...900,
            highlights: ["崇礼", "草原天路", "大境门"],
            suggestedPace: "崇礼和草原天路都值得留出完整时间，不赶路更好。"
        ),
        WeekendDestination(
            id: "chengde",
            cityName: "承德",
            tagline: "避暑山庄和外八庙，夏秋周末的稳定选项。",
            coordinate: CampusCoordinate(latitude: 40.957, longitude: 117.93),
            distanceKilometers: 230,
            travelTimeHours: 2.5,
            recommendedDays: 2...3,
            bestMonths: [5, 6, 7, 8, 9, 10],
            estimatedBudgetYuan: 400...800,
            highlights: ["避暑山庄", "普宁寺", "小布达拉宫"],
            suggestedPace: "山庄和外八庙连着看，夏秋都很顺。"
        ),
        WeekendDestination(
            id: "taiyuan",
            cityName: "太原",
            tagline: "晋祠、钟楼街和博物馆，适合把山西味道一次看够。",
            coordinate: CampusCoordinate(latitude: 37.8706, longitude: 112.5489),
            distanceKilometers: 500,
            travelTimeHours: 2.3,
            recommendedDays: 2...3,
            bestMonths: [4, 5, 6, 9, 10, 11],
            estimatedBudgetYuan: 450...850,
            highlights: ["晋祠", "山西博物院", "钟楼街"],
            suggestedPace: "晋祠、博物馆和夜游钟楼街可以排得很从容。"
        ),
        WeekendDestination(
            id: "qinhuangdao",
            cityName: "秦皇岛",
            tagline: "海边、老龙头和阿那亚，适合夏天补一口海风。",
            coordinate: CampusCoordinate(latitude: 39.935, longitude: 119.599),
            distanceKilometers: 300,
            travelTimeHours: 3.0,
            recommendedDays: 2...3,
            bestMonths: [6, 7, 8, 9],
            estimatedBudgetYuan: 600...1100,
            highlights: ["北戴河", "山海关", "老龙头"],
            suggestedPace: "海边、山海关和老龙头适合放慢脚步。"
        ),
        WeekendDestination(
            id: "qingdao",
            cityName: "青岛",
            tagline: "海边、老城和崂山，适合把周末交给海风。",
            coordinate: CampusCoordinate(latitude: 36.0671, longitude: 120.3826),
            distanceKilometers: 650,
            travelTimeHours: 4.0,
            recommendedDays: 2...3,
            bestMonths: [5, 6, 7, 8, 9, 10],
            estimatedBudgetYuan: 700...1300,
            highlights: ["栈桥", "八大关", "崂山"],
            suggestedPace: "栈桥、八大关和崂山都很适合海边放空。"
        ),
        WeekendDestination(
            id: "datong",
            cityName: "大同",
            tagline: "云冈石窟、古城墙和刀削面，节奏放慢更舒服。",
            coordinate: CampusCoordinate(latitude: 40.076, longitude: 113.300),
            distanceKilometers: 340,
            travelTimeHours: 3.5,
            recommendedDays: 3...3,
            bestMonths: [4, 5, 6, 9, 10],
            estimatedBudgetYuan: 600...1000,
            highlights: ["云冈石窟", "华严寺", "古城墙"],
            suggestedPace: "云冈和古城墙各留些时间，体验会更完整。"
        ),
        WeekendDestination(
            id: "jinan",
            cityName: "济南",
            tagline: "泉水、老城和鲁菜，适合边吃边逛。",
            coordinate: CampusCoordinate(latitude: 36.651, longitude: 117.120),
            distanceKilometers: 410,
            travelTimeHours: 3.0,
            recommendedDays: 3...3,
            bestMonths: [3, 4, 5, 6, 9, 10, 11],
            estimatedBudgetYuan: 650...1100,
            highlights: ["趵突泉", "大明湖", "千佛山"],
            suggestedPace: "泉水、老城和山景很适合边走边吃。"
        ),
        WeekendDestination(
            id: "pingyao",
            cityName: "平遥",
            tagline: "古城夜景、票号和山西面食，适合慢慢逛。",
            coordinate: CampusCoordinate(latitude: 37.185, longitude: 112.175),
            distanceKilometers: 600,
            travelTimeHours: 4.5,
            recommendedDays: 3...3,
            bestMonths: [4, 5, 9, 10, 11],
            estimatedBudgetYuan: 700...1200,
            highlights: ["平遥古城", "日升昌", "双林寺"],
            suggestedPace: "古城夜景、票号和寺院慢慢逛更有味道。"
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
