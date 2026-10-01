package com.myleafy.android.features.campus

import android.content.Context
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.decodeFromString

@Serializable data class MedicalRate(val id: String, val category: String, val target: String, val rate: Int, val note: String)
@Serializable data class MedicalAdvice(val id: String, val title: String, val rateText: String, val steps: List<String>, val materials: List<String>, val notes: List<String>, val rate: Double? = null)
@Serializable data class MedicalPolicy(
    val policyUpdatedAt: String, val hospitalInfoUpdatedAt: String, val sourceTitle: String,
    val sourceURL: String, val sourceImageURL: String, val hospitalInfoURL: String,
    val hospitalName: String, val hospitalAddress: String, val hospitalPhones: String,
    val outpatientHours: String, val reimbursementHours: String,
    val reimbursementRates: List<MedicalRate>, val medicationRules: List<String>, val excludedExpenses: List<String>,
    val rehabRules: List<String>, val scenarioAdvices: List<MedicalAdvice>, val materials: List<String>, val statuses: List<String>,
) {
    companion object { fun load(context: Context): MedicalPolicy = context.assets.open("campus/medical-policy.json").bufferedReader().use { Json.decodeFromString(it.readText()) } }
}
@Serializable data class VenueDetail(val title: String, val value: String)
@Serializable data class VenueFee(val title: String, val lines: List<VenueDetail>)
@Serializable data class CampusVenue(val id: String, val title: String, val location: String, val tags: List<String>, val details: List<VenueDetail>, val fees: List<VenueFee> = emptyList(), val notes: List<String> = emptyList())
@Serializable data class CampusVenueGroup(val id: String, val title: String, val venues: List<CampusVenue>) {
    companion object { fun load(context: Context): List<CampusVenueGroup> = context.assets.open("campus/sports-venues.json").bufferedReader().use { Json.decodeFromString(it.readText()) } }
}

fun medicalDeadline(entry: com.myleafy.android.core.data.local.MedicalLedgerEntryEntity, today: java.time.LocalDate = java.time.LocalDate.now()): String {
    if (entry.status in listOf("已报销", "已归档")) return "已结案"
    val deadline = entry.reimbursementDeadline ?: return "未设置截止日"
    val days = deadline - today.toEpochDay()
    return when { days < 0 -> "已逾期 ${-days} 天"; days <= 14 -> "${days} 天内到期"; else -> "剩余 $days 天" }
}
