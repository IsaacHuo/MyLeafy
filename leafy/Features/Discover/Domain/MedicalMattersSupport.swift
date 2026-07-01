import Foundation
import SwiftUI

enum MedicalLedgerScenario: String, CaseIterable, Identifiable, Codable {
    case campusClinic = "校医院门急诊"
    case contractOutpatient = "合同医院门急诊"
    case specialistOutpatient = "非合同/专科门急诊"
    case inpatient = "住院"
    case emergency = "急危重症"
    case remoteDuringTerm = "学期异地急诊"
    case holidayRemote = "寒暑假所在地急诊"

    var id: String { rawValue }

    var reimbursementRate: Double? {
        switch self {
        case .campusClinic:
            return 0.9
        case .contractOutpatient:
            return 0.8
        case .specialistOutpatient:
            return 0.7
        case .inpatient:
            return 0.95
        case .emergency, .remoteDuringTerm, .holidayRemote:
            return nil
        }
    }

    var icon: String {
        switch self {
        case .campusClinic: return "cross.case.fill"
        case .contractOutpatient: return "building.2.fill"
        case .specialistOutpatient: return "stethoscope"
        case .inpatient: return "bed.double.fill"
        case .emergency: return "cross.circle.fill"
        case .remoteDuringTerm: return "location.fill"
        case .holidayRemote: return "house.fill"
        }
    }

    static func normalized(_ rawValue: String) -> MedicalLedgerScenario {
        MedicalLedgerScenario(rawValue: rawValue) ?? .campusClinic
    }
}

enum MedicalLedgerStatus: String, CaseIterable, Identifiable, Codable {
    case organizing = "待整理"
    case readyToSubmit = "待提交"
    case submitted = "已提交"
    case reimbursed = "已报销"
    case returned = "被退回"
    case archived = "已归档"

    var id: String { rawValue }

    var isClosed: Bool {
        self == .reimbursed || self == .archived
    }

    static func normalized(_ rawValue: String) -> MedicalLedgerStatus {
        MedicalLedgerStatus(rawValue: rawValue) ?? .organizing
    }
}

enum MedicalLedgerMaterial: String, CaseIterable, Identifiable, Codable {
    case referral = "转诊单"
    case invoice = "收费票据"
    case feeDetail = "费用明细清单"
    case prescription = "药品处方/底方"
    case outpatientRecord = "门急诊病历"
    case emergencyDiagnosis = "急诊诊断证明"
    case dischargeSummary = "出院诊断证明"
    case inpatientInvoice = "住院收费票据"
    case diagnosisCertificate = "诊断证明书"
    case collegeStatement = "学院情况说明"

    var id: String { rawValue }

    static func decode(_ rawValue: String) -> Set<MedicalLedgerMaterial> {
        Set(rawValue.split(separator: "|").compactMap { MedicalLedgerMaterial(rawValue: String($0)) })
    }

    static func encode(_ materials: Set<MedicalLedgerMaterial>) -> String {
        materials
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.rawValue)
            .joined(separator: "|")
    }
}

enum MedicalLedgerDeadlineState: Equatable {
    case none
    case normal(days: Int)
    case dueSoon(days: Int)
    case overdue(days: Int)
    case closed
}

enum MedicalLedgerCalculator {
    static func estimatedReimbursement(totalExpense: Double, scenario: MedicalLedgerScenario) -> Double? {
        guard totalExpense > 0, let rate = scenario.reimbursementRate else { return nil }
        return (totalExpense * rate * 100).rounded() / 100
    }

    static func deadlineState(
        deadline: Date?,
        status: MedicalLedgerStatus,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MedicalLedgerDeadlineState {
        guard !status.isClosed else { return .closed }
        guard let deadline else { return .none }
        let today = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: deadline)
        let days = calendar.dateComponents([.day], from: today, to: target).day ?? 0
        if days < 0 {
            return .overdue(days: abs(days))
        }
        if days <= 14 {
            return .dueSoon(days: days)
        }
        return .normal(days: days)
    }
}

struct MedicalReimbursementRate: Identifiable, Equatable {
    let id: String
    let category: String
    let target: String
    let rate: Int
    let note: String
}

struct MedicalPolicyScenarioAdvice: Identifiable, Equatable {
    let id: MedicalLedgerScenario
    let title: String
    let rateText: String
    let steps: [String]
    let materials: [MedicalLedgerMaterial]
    let notes: [String]
}

struct MedicalPolicySnapshot: Equatable {
    let policyUpdatedAt = "2024-05-23"
    let hospitalInfoUpdatedAt = "2026-06-01"
    let sourceTitle = "北京林业大学学生版公费医疗一图读懂"
    let sourceURL = URL(string: "https://news.qq.com/rain/a/20240523A04DUW00")!
    let sourceImageURL = URL(string: "https://inews.gtimg.com/om_bt/Otw6ahOJpLAFy_nt4oNhGUyUPvbujM4hKY7irA7T3WxOAAA/641")!
    let hospitalInfoURL = URL(string: "https://map.beijing.gov.cn/place?categoryId=sqwsfwjg&placeId=6a1d4d9d107bae2ad874f4bc")!

    let reimbursementRates: [MedicalReimbursementRate] = [
        MedicalReimbursementRate(id: "clinic-campus", category: "门诊、急诊", target: "校医院", rate: 90, note: "学生校内就诊比例"),
        MedicalReimbursementRate(id: "clinic-contract", category: "门诊、急诊", target: "合同医院", rate: 80, note: "北医三院等合同医院"),
        MedicalReimbursementRate(id: "clinic-specialist", category: "门诊、急诊", target: "非合同医院及专科医院", rate: 70, note: "按转诊和专科规则办理"),
        MedicalReimbursementRate(id: "inpatient", category: "住院", target: "合同医院、专科医院、急诊方式住院的医保定点医院", rate: 95, note: "住院费用比例")
    ]

    let hospitalName = "北京林业大学社区卫生服务中心（北京林业大学医院）"
    let hospitalAddress = "北京市海淀区清华东路35号"
    let hospitalPhones = "62338236、62336005"
    let outpatientHours = "周一至周五普通门诊 08:00-11:30、13:30-17:30；周五 13:30-16:00 为全院业务培训停诊；周末及法定节假日值班门诊 08:00-11:30、13:30-17:30。"
    let reimbursementHours = "学期期间每周二、四 13:30-16:30，地点为师生综合服务中心一层大厅；寒暑假另行通知。"

    let medicationRules = [
        "急性病不超过 3 日量。",
        "慢性病不超过 7 日量。",
        "行动不便不超过 2 周量。",
        "特殊慢性病如高血压、糖尿病、冠心病、慢性肝炎、肝硬化、结核病、精神病、癌症、脑血管病、前列腺肥大疾病且病情稳定需长期服用同一类药物，不超过 1 月量。",
        "超量药费自付；第一次取的药未用完，第二次提前到医院拿药，报销时扣除重复用药费用。"
    ]

    let excludedExpenses = [
        "急救中心开具的救护车费、出诊费、材料费、转运费、清洁费等。",
        "住院期间的陪护费、伙食费、卫生费、文娱费、赔偿费、记账费、病历费、担架费、押瓶费等。",
        "各种体格检查费、预防服药、疫苗接种等。",
        "美容、整容、矫形、生理缺陷、健美等手术、治疗、药品、器具费用。",
        "防暑降温药品费用。",
        "减肥、戒烟、食疗门诊费用。",
        "因交通肇事、打架斗殴、酗酒、医疗事故造成伤残所发生的费用。",
        "北京市医保规定自费的项目。"
    ]

    let rehabRules = [
        "因中枢神经系统疾病及损伤进行物理、康复治疗的，仅报销发病后 6 个月内的费用。",
        "因其他疾病进行物理、康复治疗的，仅报销发病后 3 个月内的费用。",
        "手术后进行物理、康复治疗的，期限自手术后开始计算。"
    ]

    var scenarioAdvices: [MedicalPolicyScenarioAdvice] {
        [
            MedicalPolicyScenarioAdvice(
                id: .campusClinic,
                title: "校医院常见病、多发病",
                rateText: "约 90%",
                steps: ["先到校医院挂号", "凭校园一卡通挂号，到相关科室就诊", "按票据和处方留存材料"],
                materials: [.invoice, .feeDetail, .prescription, .outpatientRecord],
                notes: ["校医院有中医门诊，中医科就诊不予转诊。"]
            ),
            MedicalPolicyScenarioAdvice(
                id: .contractOutpatient,
                title: "合同医院门急诊",
                rateText: "约 80%",
                steps: ["先到校医院就诊", "由校医院根据病情开具转诊单", "在转诊期限内前往合同医院相关科室", "回校按材料报销"],
                materials: [.referral, .invoice, .feeDetail, .prescription, .outpatientRecord],
                notes: ["切记先开转诊单再前往合同医院门诊就医，超出转诊单期限需重新开具。"]
            ),
            MedicalPolicyScenarioAdvice(
                id: .specialistOutpatient,
                title: "非合同医院及专科医院",
                rateText: "约 70%",
                steps: ["前往非合同/非就近医院或非经转诊专科医院前，先确认转诊要求", "按北医三院转诊或专科住院转诊规则办理", "留存完整票据和病历"],
                materials: [.referral, .invoice, .feeDetail, .prescription, .outpatientRecord],
                notes: ["前往合同医院北医三院以外的医保定点医疗机构，须由合同医院北医三院开具转诊单。"]
            ),
            MedicalPolicyScenarioAdvice(
                id: .inpatient,
                title: "住院",
                rateText: "约 95%",
                steps: ["按校医院或合同医院转诊规则办理", "住院期间保存住院票据和诊断材料", "出院后整理住院病案首页、诊断证明和费用明细"],
                materials: [.referral, .inpatientInvoice, .dischargeSummary, .diagnosisCertificate, .feeDetail],
                notes: ["住院报销按政策审核，急诊方式住院需附急诊相关材料。"]
            ),
            MedicalPolicyScenarioAdvice(
                id: .emergency,
                title: "急危重症",
                rateText: "按就医类型审核",
                steps: ["可在北京市任意一家一级及以上医保定点医院急诊科就诊", "无需开具转诊单", "必须挂急诊号并留存急诊材料"],
                materials: [.emergencyDiagnosis, .invoice, .feeDetail, .prescription, .outpatientRecord],
                notes: ["急危重症直接急诊就医，材料齐全后按规定报销。"]
            ),
            MedicalPolicyScenarioAdvice(
                id: .remoteDuringTerm,
                title: "学期异地急诊",
                rateText: "按北京市医保政策和支付标准审核",
                steps: ["因学校公派异地实习等原因临时患急性病", "在当地就近医保定点医疗机构就医", "回校后凭急诊材料和学院证明报销"],
                materials: [.emergencyDiagnosis, .invoice, .feeDetail, .prescription, .collegeStatement],
                notes: ["慢性疾病的检查、治疗、化验等费用不予报销。"]
            ),
            MedicalPolicyScenarioAdvice(
                id: .holidayRemote,
                title: "寒暑假回所在地急诊",
                rateText: "按标准累计限额审核",
                steps: ["寒暑假期间临时患急性病", "在当地就近医保定点医疗机构就医", "回校后凭急诊病历、急诊收据、急诊处方等材料报销"],
                materials: [.emergencyDiagnosis, .invoice, .feeDetail, .prescription, .outpatientRecord],
                notes: ["累计不得超过政策图示的公费医疗标准，超过部分自负；慢性疾病检查、治疗、化验等费用不予报销。"]
            )
        ]
    }

    static let current = MedicalPolicySnapshot()

    func advice(for scenario: MedicalLedgerScenario) -> MedicalPolicyScenarioAdvice {
        scenarioAdvices.first(where: { $0.id == scenario }) ?? scenarioAdvices[0]
    }
}

extension MedicalLedgerEntry {
    var scenario: MedicalLedgerScenario {
        get { MedicalLedgerScenario.normalized(scenarioRawValue) }
        set { scenarioRawValue = newValue.rawValue }
    }

    var status: MedicalLedgerStatus {
        get { MedicalLedgerStatus.normalized(statusRawValue) }
        set { statusRawValue = newValue.rawValue }
    }

    var materials: Set<MedicalLedgerMaterial> {
        get { MedicalLedgerMaterial.decode(materialChecklistRawValue) }
        set { materialChecklistRawValue = MedicalLedgerMaterial.encode(newValue) }
    }

    var displayTitle: String {
        let hospital = hospitalName.trimmingCharacters(in: .whitespacesAndNewlines)
        let diagnosis = diagnosisNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !hospital.isEmpty { return hospital }
        if !diagnosis.isEmpty { return diagnosis }
        return scenario.rawValue
    }

    var estimatedOrCalculatedReimbursement: Double? {
        estimatedReimbursement ?? MedicalLedgerCalculator.estimatedReimbursement(totalExpense: totalExpense, scenario: scenario)
    }

    func deadlineState(now: Date = Date(), calendar: Calendar = .current) -> MedicalLedgerDeadlineState {
        MedicalLedgerCalculator.deadlineState(deadline: reimbursementDeadline, status: status, now: now, calendar: calendar)
    }
}

enum MedicalLedgerPhotoStore {
    struct StoredPhoto {
        let localFilename: String
        let jpegData: Data
    }

    static func normalizedJPEGData(from imageData: Data) throws -> Data {
        guard let image = LeafyPlatformImage(data: imageData),
              let jpegData = image.jpegData(compressionQuality: 0.88) else {
            throw MedicalLedgerPhotoStoreError.invalidImage
        }
        return jpegData
    }

    static func importImageData(_ imageData: Data, originalFilename: String) throws -> StoredPhoto {
        let jpegData = try normalizedJPEGData(from: imageData)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let localFilename = "\(UUID().uuidString).jpg"
        let destination = directoryURL.appendingPathComponent(localFilename)
        try jpegData.write(to: destination, options: .atomic)
        return StoredPhoto(localFilename: localFilename, jpegData: jpegData)
    }

    static func fileURL(for photo: MedicalLedgerPhoto) -> URL? {
        let url = directoryURL.appendingPathComponent(photo.localFilename)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    static func image(for photo: MedicalLedgerPhoto) -> LeafyPlatformImage? {
        guard let url = fileURL(for: photo) else { return nil }
        return LeafyPlatformImage(contentsOfFile: url.path(percentEncoded: false))
    }

    static func fileData(for photo: MedicalLedgerPhoto) -> Data? {
        guard let url = fileURL(for: photo) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func deleteFile(named filename: String) throws {
        let url = directoryURL.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func deleteAllFiles() {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    private static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("MedicalLedgerPhotos", isDirectory: true)
    }
}

enum MedicalLedgerPhotoStoreError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        "无法读取这张图片。"
    }
}

enum MedicalLedgerExporter {
    struct ExportManifest: Codable {
        let exportedAt: Date
        let policyUpdatedAt: String
        let hospitalInfoUpdatedAt: String
        let entries: [Entry]
        let photos: [Photo]
    }

    struct Entry: Codable {
        let id: String
        let visitDate: Date
        let hospitalName: String
        let department: String
        let diagnosisNote: String
        let scenario: String
        let totalExpense: Double
        let estimatedReimbursement: Double?
        let actualReimbursement: Double?
        let status: String
        let reimbursementDeadline: Date?
        let materials: [String]
        let note: String
        let createdAt: Date
        let updatedAt: Date
    }

    struct Photo: Codable {
        let id: String
        let entryID: String
        let originalFilename: String
        let archivePath: String
        let importedAt: Date
    }

    static func makeCSVData(entries: [MedicalLedgerEntry]) -> Data {
        let header = [
            "id", "就诊日期", "医院", "科室", "诊断/病情备注", "场景", "总费用", "预计报销", "实际报销", "状态", "报销截止日", "材料", "备注"
        ]
        let rows = sortedEntries(entries).map { entry in
            [
                entry.id.uuidString,
                entry.visitDate.formatted(.iso8601.year().month().day()),
                entry.hospitalName,
                entry.department,
                entry.diagnosisNote,
                entry.scenario.rawValue,
                amountText(entry.totalExpense),
                optionalAmountText(entry.estimatedOrCalculatedReimbursement),
                optionalAmountText(entry.actualReimbursement),
                entry.status.rawValue,
                entry.reimbursementDeadline?.formatted(.iso8601.year().month().day()) ?? "",
                entry.materials.sorted { $0.rawValue < $1.rawValue }.map(\.rawValue).joined(separator: "、"),
                entry.note
            ]
        }
        let csv = ([header] + rows).map { row in
            row.map { value in
                let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
                if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
                    return "\"\(escaped)\""
                }
                return escaped
            }.joined(separator: ",")
        }.joined(separator: "\n")
        return Data(("\u{feff}" + csv + "\n").utf8)
    }

    static func makeManifestData(entries: [MedicalLedgerEntry], photos: [MedicalLedgerPhoto]) throws -> Data {
        let manifest = makeManifest(entries: entries, photos: photos)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(manifest)
    }

    static func makeZipData(
        entries: [MedicalLedgerEntry],
        photos: [MedicalLedgerPhoto],
        photoDataProvider: (MedicalLedgerPhoto) -> Data?
    ) throws -> Data {
        var files: [(path: String, data: Data)] = [
            ("medical-ledger.csv", makeCSVData(entries: entries)),
            ("manifest.json", try makeManifestData(entries: entries, photos: photos))
        ]
        for photo in photos.sorted(by: { $0.importedAt < $1.importedAt }) {
            guard let data = photoDataProvider(photo) else { continue }
            files.append((photoArchivePath(photo), data))
        }
        return ZipArchiveWriter.makeArchive(files: files)
    }

    static func exportArchive(entries: [MedicalLedgerEntry], photos: [MedicalLedgerPhoto]) throws -> URL {
        let data = try makeZipData(entries: entries, photos: photos) { photo in
            MedicalLedgerPhotoStore.fileData(for: photo)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "LeafyMedicalLedger-\(formatter.string(from: Date())).zip"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func makeManifest(entries: [MedicalLedgerEntry], photos: [MedicalLedgerPhoto]) -> ExportManifest {
        ExportManifest(
            exportedAt: Date(),
            policyUpdatedAt: MedicalPolicySnapshot.current.policyUpdatedAt,
            hospitalInfoUpdatedAt: MedicalPolicySnapshot.current.hospitalInfoUpdatedAt,
            entries: sortedEntries(entries).map { entry in
                Entry(
                    id: entry.id.uuidString,
                    visitDate: entry.visitDate,
                    hospitalName: entry.hospitalName,
                    department: entry.department,
                    diagnosisNote: entry.diagnosisNote,
                    scenario: entry.scenario.rawValue,
                    totalExpense: entry.totalExpense,
                    estimatedReimbursement: entry.estimatedOrCalculatedReimbursement,
                    actualReimbursement: entry.actualReimbursement,
                    status: entry.status.rawValue,
                    reimbursementDeadline: entry.reimbursementDeadline,
                    materials: entry.materials.sorted { $0.rawValue < $1.rawValue }.map(\.rawValue),
                    note: entry.note,
                    createdAt: entry.createdAt,
                    updatedAt: entry.updatedAt
                )
            },
            photos: photos.sorted(by: { $0.importedAt < $1.importedAt }).map { photo in
                Photo(
                    id: photo.id.uuidString,
                    entryID: photo.entryID,
                    originalFilename: photo.originalFilename,
                    archivePath: photoArchivePath(photo),
                    importedAt: photo.importedAt
                )
            }
        )
    }

    private static func sortedEntries(_ entries: [MedicalLedgerEntry]) -> [MedicalLedgerEntry] {
        entries.sorted {
            if $0.visitDate != $1.visitDate {
                return $0.visitDate > $1.visitDate
            }
            return $0.createdAt > $1.createdAt
        }
    }

    private static func photoArchivePath(_ photo: MedicalLedgerPhoto) -> String {
        "photos/\(photo.entryID)/\(photo.localFilename)"
    }

    private static func amountText(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func optionalAmountText(_ value: Double?) -> String {
        guard let value else { return "" }
        return amountText(value)
    }

}

enum ZipArchiveWriter {
    struct CentralDirectoryRecord {
        let pathData: Data
        let crc: UInt32
        let size: UInt32
        let offset: UInt32
        let modTime: UInt16
        let modDate: UInt16
    }

    static func makeArchive(files: [(path: String, data: Data)], date: Date = Date()) -> Data {
        var archive = Data()
        var centralRecords: [CentralDirectoryRecord] = []
        let dosDate = dosDateTime(from: date)

        for file in files {
            let pathData = Data(file.path.utf8)
            let offset = UInt32(archive.count)
            let crc = CRC32.checksum(file.data)
            let size = UInt32(file.data.count)

            archive.appendUInt32(0x04034b50)
            archive.appendUInt16(20)
            archive.appendUInt16(0)
            archive.appendUInt16(0)
            archive.appendUInt16(dosDate.time)
            archive.appendUInt16(dosDate.date)
            archive.appendUInt32(crc)
            archive.appendUInt32(size)
            archive.appendUInt32(size)
            archive.appendUInt16(UInt16(pathData.count))
            archive.appendUInt16(0)
            archive.append(pathData)
            archive.append(file.data)

            centralRecords.append(CentralDirectoryRecord(
                pathData: pathData,
                crc: crc,
                size: size,
                offset: offset,
                modTime: dosDate.time,
                modDate: dosDate.date
            ))
        }

        let centralDirectoryOffset = UInt32(archive.count)
        for record in centralRecords {
            archive.appendUInt32(0x02014b50)
            archive.appendUInt16(20)
            archive.appendUInt16(20)
            archive.appendUInt16(0)
            archive.appendUInt16(0)
            archive.appendUInt16(record.modTime)
            archive.appendUInt16(record.modDate)
            archive.appendUInt32(record.crc)
            archive.appendUInt32(record.size)
            archive.appendUInt32(record.size)
            archive.appendUInt16(UInt16(record.pathData.count))
            archive.appendUInt16(0)
            archive.appendUInt16(0)
            archive.appendUInt16(0)
            archive.appendUInt16(0)
            archive.appendUInt32(0)
            archive.appendUInt32(record.offset)
            archive.append(record.pathData)
        }

        let centralDirectorySize = UInt32(archive.count) - centralDirectoryOffset
        archive.appendUInt32(0x06054b50)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt16(UInt16(centralRecords.count))
        archive.appendUInt16(UInt16(centralRecords.count))
        archive.appendUInt32(centralDirectorySize)
        archive.appendUInt32(centralDirectoryOffset)
        archive.appendUInt16(0)
        return archive
    }

    private static func dosDateTime(from date: Date) -> (date: UInt16, time: UInt16) {
        let components = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        let year = max((components.year ?? 1980) - 1980, 0)
        let month = components.month ?? 1
        let day = components.day ?? 1
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let second = (components.second ?? 0) / 2
        let dosDate = UInt16((year << 9) | (month << 5) | day)
        let dosTime = UInt16((hour << 11) | (minute << 5) | second)
        return (dosDate, dosTime)
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            if crc & 1 == 1 {
                crc = (crc >> 1) ^ 0xedb88320
            } else {
                crc >>= 1
            }
        }
        return crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xff)
            crc = (crc >> 8) ^ table[index]
        }
        return crc ^ 0xffffffff
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}
