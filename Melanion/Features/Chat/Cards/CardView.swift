import SwiftUI

struct CardView: View {
    let format: ResponseFormat
    let rows: [[String: Any?]]

    var body: some View {
        switch format {
        case .stat:
            StatCard.from(rows: rows)
        case .rankedList:
            RankedListCard.from(rows: rows)
        case .trend:
            TrendCard.from(rows: rows)
        case .detail:
            DetailCard.from(rows: rows)
        }
    }
}
