package com.myleafy.android.features.campus

import java.time.LocalDate
import java.time.LocalTime

enum class GuestAcademicKind(val title: String, val columns: List<String>, val labels: List<String>) {
    GRADE("成绩", listOf("term", "courseName", "credit", "score", "type"), listOf("学期", "课程名称", "学分", "原始成绩", "课程性质")),
    EXAM("考试", listOf("courseID", "name", "date", "start", "end", "location"), listOf("课程编号", "名称", "日期 YYYY-MM-DD", "开始 HH:mm", "结束 HH:mm", "地点")),
}

object GuestAcademicCsv {
    fun validate(kind: GuestAcademicKind, row: List<String>) {
        require(row.size == kind.columns.size) { "列数不正确" }
        when (kind) {
            GuestAcademicKind.GRADE -> {
                require(row[0].isNotBlank()) { "学期不能为空" }
                require(row[1].isNotBlank()) { "课程名称不能为空" }
                require(row[2].toDoubleOrNull()?.let { it.isFinite() && it >= 0 } == true) { "学分须为大于或等于零的数字" }
                require(row[3].isNotBlank()) { "成绩不能为空" }
            }
            GuestAcademicKind.EXAM -> {
                require(row[1].isNotBlank()) { "name 不能为空" }
                LocalDate.parse(row[2]); val start = LocalTime.parse(row[3]); val end = LocalTime.parse(row[4])
                require(end > start) { "考试结束时间须晚于开始时间" }
            }
        }
    }
    fun parse(text: String, kind: GuestAcademicKind): List<List<String>> {
        val source = text.removePrefix("\uFEFF")
        val records = mutableListOf<Pair<Int, List<String>>>()
        val row = mutableListOf<String>(); val field = StringBuilder()
        var quoted = false; var closed = false; var position = 0
        var line = 1; var rowLine = 1
        fun finishField() { row += field.toString(); field.clear(); closed = false }
        fun finishRow() { finishField(); if (row.any(String::isNotBlank)) records += rowLine to row.toList(); row.clear(); rowLine = line + 1 }
        while (position < source.length) {
            val char = source[position]
            if (quoted) {
                if (char == '"') { if (source.getOrNull(position + 1) == '"') { field.append('"'); position++ } else { quoted = false; closed = true } }
                else field.append(char)
            } else when (char) {
                '"' -> { require(field.isEmpty() && !closed) { "CSV 第 $line 行：引号位置错误" }; quoted = true }
                ',' -> finishField()
                '\n' -> finishRow()
                '\r' -> { if (source.getOrNull(position + 1) == '\n') position++; finishRow() }
                else -> { require(!closed || char.isWhitespace()) { "CSV 第 $line 行：引号后包含非法内容" }; if (!closed) field.append(char) }
            }
            if (char == '\n' || (char == '\r' && (!quoted || source.getOrNull(position + 1) != '\n'))) line++
            position++
        }
        require(!quoted) { "CSV 第 $rowLine 行：引号未闭合" }
        if (field.isNotEmpty() || row.isNotEmpty() || closed) finishRow()
        require(records.isNotEmpty()) { "CSV 文件为空" }
        val headers = records.first().second.map { it.trim() }
        require(headers.distinct().size == headers.size) { "CSV 表头重复" }
        val missing = kind.columns - headers.toSet()
        require(missing.isEmpty()) { "CSV 缺少必要列：${missing.joinToString()}" }
        val rows = records.drop(1).map { (startLine, record) ->
            try { require(record.size == headers.size) { "列数与表头不一致" }
                kind.columns.map { record[headers.indexOf(it)].trim() }.also { validate(kind, it) }
            } catch (failure: Exception) { throw IllegalArgumentException("CSV 第 $startLine 行：${failure.message}", failure) }
        }
        require(rows.isNotEmpty()) { "CSV 没有数据行" }
        return rows
    }
    fun template(kind: GuestAcademicKind): String = "\uFEFF" + kind.columns.joinToString(",") + "\n" + when (kind) {
        GuestAcademicKind.GRADE -> "2026-2027-1,示例课程,2,85,必修\n"
        GuestAcademicKind.EXAM -> "EXAMPLE,示例考试,2026-12-01,09:00,11:00,示例教室\n"
    }
}
