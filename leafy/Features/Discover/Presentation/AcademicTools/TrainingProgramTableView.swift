import SwiftUI

struct TrainingProgramTableView: View {
    let table: TrainingProgramTable

    var body: some View {
        DisclosureGroup(table.title) {
            ScrollView(.horizontal) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(cell.isEmpty ? "—" : cell)
                                    .font(.caption)
                                    .textSelection(.enabled)
                                    .frame(width: 120, alignment: .leading)
                                    .padding(8)
                            }
                        }
                        Divider()
                    }
                }
            }
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium))
        }
    }
}
