package com.myleafy.android.core.data.local

import androidx.room.TypeConverter

/**
 * Room 类型转换器：将教务模型中的 Int 列表按稳定文本形式持久化。
 * weeks 示例 "1,3,5,7"，duration 示例 "1,2"。
 */
class Converters {
    @TypeConverter
    fun fromIntList(values: List<Int>): String = values.joinToString(",")

    @TypeConverter
    fun toIntList(encoded: String): List<Int> =
        encoded.split(",").mapNotNull { it.trim().toIntOrNull() }
}
