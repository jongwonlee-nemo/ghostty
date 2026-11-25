import AppKit
import Testing
@testable import Ghostty

struct QuickTerminalCarouselTests {
    @Test func carouselShowsFirstTwoAndKeepsOrder() throws {
        let (a, b, c, d, e) = (MockView(), MockView(), MockView(), MockView(), MockView())
        // Column b is split top/bottom with e and must rotate as one column.
        let colB = try SplitTree<MockView>(view: b).inserting(view: e, at: b, direction: .down).root!
        let cols: [SplitTree<MockView>.Node] = [.leaf(view: a), colB, .leaf(view: c), .leaf(view: d)]

        let tree = SplitTree<MockView>.carousel(cols, ratio: 0.3)
        #expect(tree.columns == cols)
        #expect(tree.pairRatio == 0.3)
        #expect(tree.zoomed?.leaves() == [a, b, e])
        #expect(Array(tree) == [a, b, e, c, d])

        // Fewer than three columns need no zoom.
        #expect(SplitTree<MockView>.carousel(Array(cols.prefix(2)), ratio: 0.5).zoomed == nil)
    }
}
