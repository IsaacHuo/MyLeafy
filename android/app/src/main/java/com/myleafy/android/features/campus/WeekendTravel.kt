package com.myleafy.android.features.campus

import java.time.LocalDate
import java.time.Month

/**
 * 周末去哪的本地静态推荐（对应 iOS `WeekendTravelRecommendationEngine`）。
 * 数据为内置常量，不请求网络；仅在北林校园显示。
 */
data class WeekendDestination(
    val id: String,
    val cityName: String,
    val tagline: String,
    val distanceKilometers: Int,
    val travelTimeMinutes: Int,
    val recommendedDays: IntRange,
    val bestMonths: List<Int>,
    val estimatedBudget: IntRange,
    val highlights: List<String>,
) {
    val tripLengthText: String
        get() = if (recommendedDays.first == recommendedDays.last) {
            "${recommendedDays.first}天"
        } else {
            "${recommendedDays.first}-${recommendedDays.last}天"
        }

    val budgetText: String get() = "${estimatedBudget.first}-${estimatedBudget.last}元"

    val seasonText: String get() = bestMonths.sorted().joinToString("/")

    val travelTimeText: String
        get() {
            val hours = travelTimeMinutes / 60
            val remainder = travelTimeMinutes % 60
            return if (remainder == 0) "${hours}小时" else "${hours}小时${remainder}分"
        }

    val highlightRail: List<String>
        get() = highlights.take(if (highlights.any { it.length > 4 }) 4 else 5)
}

object WeekendTravelRecommendationEngine {

    fun recommend(month: Int = LocalDate.now().monthValue): List<WeekendDestination> {
        val normalized = if (month in 1..12) month else Month.values().first().value
        return destinations.sortedWith(
            compareByDescending<WeekendDestination> { score(it, normalized) }
                .thenBy { it.distanceKilometers }
                .thenBy { it.cityName },
        )
    }

    private fun score(destination: WeekendDestination, month: Int): Int {
        val seasonScore = if (month in destination.bestMonths) 100 else 0
        val distanceScore = maxOf(0, 50 - destination.distanceKilometers / 12)
        val budgetScore = maxOf(0, 30 - destination.estimatedBudget.first / 50)
        return seasonScore + distanceScore + budgetScore
    }

    val destinations: List<WeekendDestination> = listOf(
        WeekendDestination(
            id = "tianjin",
            cityName = "天津",
            tagline = "海门东望天连水，千年沽市浪接云。",
            distanceKilometers = 120,
            travelTimeMinutes = 90,
            recommendedDays = 2..3,
            bestMonths = listOf(3, 4, 5, 6, 9, 10, 11),
            estimatedBudget = 300..700,
            highlights = listOf("海河", "五大道", "意式风情区"),
        ),
        WeekendDestination(
            id = "cangzhou",
            cityName = "沧州",
            tagline = "千帆夜泊沧州月，一塔晨迎渤海潮。",
            distanceKilometers = 180,
            travelTimeMinutes = 60,
            recommendedDays = 2..3,
            bestMonths = listOf(3, 4, 5, 6, 9, 10, 11),
            estimatedBudget = 250..550,
            highlights = listOf("南川老街", "沧州铁狮子", "吴桥杂技大世界"),
        ),
        WeekendDestination(
            id = "shijiazhuang_zhengding",
            cityName = "石家庄（正定古城）",
            tagline = "九楼月照燕南地，四塔风鸣赵北天。",
            distanceKilometers = 280,
            travelTimeMinutes = 90,
            recommendedDays = 2..3,
            bestMonths = listOf(3, 4, 5, 6, 9, 10, 11),
            estimatedBudget = 300..650,
            highlights = listOf("正定古城", "隆兴寺", "荣国府"),
        ),
        WeekendDestination(
            id = "tangshan",
            cityName = "唐山",
            tagline = "凤岭新霞衔晓日，南湖旧浪换清波。",
            distanceKilometers = 160,
            travelTimeMinutes = 72,
            recommendedDays = 2..3,
            bestMonths = listOf(4, 5, 6, 9, 10),
            estimatedBudget = 250..600,
            highlights = listOf("河头老街", "唐山宴", "清东陵"),
        ),
        WeekendDestination(
            id = "baoding",
            cityName = "保定",
            tagline = "莲池夜月沉珠影，督府秋风动铁衣。",
            distanceKilometers = 160,
            travelTimeMinutes = 120,
            recommendedDays = 2..3,
            bestMonths = listOf(4, 5, 9, 10),
            estimatedBudget = 300..650,
            highlights = listOf("直隶总督署", "古莲花池", "白洋淀"),
        ),
        WeekendDestination(
            id = "zhangjiakou",
            cityName = "张家口",
            tagline = "大境门开迎瀚海，长城垣曲绕寒云。",
            distanceKilometers = 220,
            travelTimeMinutes = 150,
            recommendedDays = 2..3,
            bestMonths = listOf(1, 2, 6, 7, 8, 9, 10, 12),
            estimatedBudget = 450..900,
            highlights = listOf("崇礼", "草原天路", "大境门"),
        ),
        WeekendDestination(
            id = "chengde",
            cityName = "承德",
            tagline = "山庄水色空涵碧，庙宇钟声谷荡幽。",
            distanceKilometers = 230,
            travelTimeMinutes = 150,
            recommendedDays = 2..3,
            bestMonths = listOf(5, 6, 7, 8, 9, 10),
            estimatedBudget = 400..800,
            highlights = listOf("避暑山庄", "普宁寺", "小布达拉宫"),
        ),
        WeekendDestination(
            id = "taiyuan",
            cityName = "太原",
            tagline = "晋祠周柏汾河水，唐碑宋塑西山林。",
            distanceKilometers = 500,
            travelTimeMinutes = 138,
            recommendedDays = 2..3,
            bestMonths = listOf(4, 5, 6, 9, 10, 11),
            estimatedBudget = 450..850,
            highlights = listOf("晋祠", "山西博物院", "钟楼街"),
        ),
        WeekendDestination(
            id = "qinhuangdao",
            cityName = "秦皇岛",
            tagline = "秦皇东临遗痕在，魏武挥鞭碣石存。",
            distanceKilometers = 300,
            travelTimeMinutes = 180,
            recommendedDays = 2..3,
            bestMonths = listOf(6, 7, 8, 9),
            estimatedBudget = 600..1100,
            highlights = listOf("北戴河", "山海关", "老龙头"),
        ),
        WeekendDestination(
            id = "qingdao",
            cityName = "青岛",
            tagline = "碧海红楼浮日影，青峦翠屿落鸥声。",
            distanceKilometers = 650,
            travelTimeMinutes = 240,
            recommendedDays = 2..3,
            bestMonths = listOf(5, 6, 7, 8, 9, 10),
            estimatedBudget = 700..1300,
            highlights = listOf("栈桥", "八大关", "崂山"),
        ),
        WeekendDestination(
            id = "datong",
            cityName = "大同",
            tagline = "塞上佛光穿壁出，悬寺空檐倚天悬。",
            distanceKilometers = 340,
            travelTimeMinutes = 210,
            recommendedDays = 3..3,
            bestMonths = listOf(4, 5, 6, 9, 10),
            estimatedBudget = 600..1000,
            highlights = listOf("云冈石窟", "华严寺", "古城墙"),
        ),
        WeekendDestination(
            id = "jinan",
            cityName = "济南",
            tagline = "七十二泉珠迸月，半城山色水浮烟。",
            distanceKilometers = 410,
            travelTimeMinutes = 180,
            recommendedDays = 3..3,
            bestMonths = listOf(3, 4, 5, 6, 9, 10, 11),
            estimatedBudget = 650..1100,
            highlights = listOf("趵突泉", "大明湖", "千佛山"),
        ),
        WeekendDestination(
            id = "pingyao",
            cityName = "平遥",
            tagline = "墙楼影压秦时月，市井声喧晋代秋。",
            distanceKilometers = 600,
            travelTimeMinutes = 270,
            recommendedDays = 3..3,
            bestMonths = listOf(4, 5, 9, 10, 11),
            estimatedBudget = 700..1200,
            highlights = listOf("平遥古城", "日升昌", "双林寺"),
        ),
    )
}
