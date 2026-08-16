/// Bounds-checked element access, for indices that come from outside the program
/// (command-line arguments here) where a trap would be the wrong response.
extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
