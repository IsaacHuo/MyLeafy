import Foundation
import UIKit

enum MedicalLedgerPhotoStore {
    struct StoredPhoto {
        let localFilename: String
        let jpegData: Data
    }

    static func normalizedJPEGData(from imageData: Data) throws -> Data {
        guard let image = UIImage(data: imageData),
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

    static func image(for photo: MedicalLedgerPhoto) -> UIImage? {
        guard let url = fileURL(for: photo) else { return nil }
        return UIImage(contentsOfFile: url.path(percentEncoded: false))
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
        let filename = "MyLeafyMedicalLedger-\(formatter.string(from: Date())).zip"
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
