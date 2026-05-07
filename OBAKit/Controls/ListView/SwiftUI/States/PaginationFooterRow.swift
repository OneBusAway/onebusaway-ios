// MARK: - PaginationFooterRow

/// A sentinel row appended to the end of a list or section to drive infinite scroll.
/// Shows a spinner while loading and fires `onLoadMore` when it first becomes visible.
struct PaginationFooterRow: View {
    let isLoading: Bool
    let onLoadMore: () -> Void

    var body: some View {
        ProgressView()
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
            .listRowSeparator(.hidden)
            .onAppear {
                guard !isLoading else { return }
                onLoadMore()
            }
    }
}