import Foundation
import Testing
@testable import NullnoteUI

/// 編集画面とプレビューの選択の行き来で、いつ色を付けていつ消すか（#M0045）。
@Suite("選択の行き来")
struct SelectionLinkTests {

    let range = NSRange(location: 10, length: 5)

    @Test("編集画面で選ぶと、プレビューに色が付く")
    func editorToPreview() {
        var link = SelectionLink()
        link.editorSelectionChanged([range], line: 3)
        #expect(link.previewMarks == [range])
        #expect(link.editorMarks.isEmpty)
        #expect(link.previewReveal?.line == 3)
    }

    @Test("プレビューで選ぶと、編集画面に色が付く")
    func previewToEditor() {
        var link = SelectionLink()
        link.previewSelectionChanged(range)
        #expect(link.editorMarks == [range])
        #expect(link.previewMarks.isEmpty)
        #expect(link.editorReveal?.range == range)
    }

    @Test("編集画面をクリックしてカーソルだけになると、両側の色が消える")
    func clickInEditorClears() {
        var link = SelectionLink()
        link.previewSelectionChanged(range)
        link.editorSelectionChanged([NSRange(location: 3, length: 0)], line: 1)
        #expect(link.editorMarks.isEmpty)
        #expect(link.previewMarks.isEmpty)
    }

    @Test("プレビューをクリックして選択が無くなると、編集画面の色が消える")
    func clickInPreviewClears() {
        var link = SelectionLink()
        link.previewSelectionChanged(range)
        link.previewSelectionChanged(nil)
        #expect(link.editorMarks.isEmpty)
    }

    @Test("プレビューで選び直すと、編集画面で選んだときの色は消える")
    func previewSelectionReplacesEditorMarks() {
        var link = SelectionLink()
        link.editorSelectionChanged([range], line: 3)
        link.previewSelectionChanged(NSRange(location: 40, length: 2))
        #expect(link.previewMarks.isEmpty)
        #expect(link.editorMarks == [NSRange(location: 40, length: 2)])
    }

    @Test("複数選択（⌘D）は、選んでいる場所すべてに色が付く")
    func multipleSelections() {
        var link = SelectionLink()
        let second = NSRange(location: 30, length: 5)
        link.editorSelectionChanged([range, second], line: 3)
        #expect(link.previewMarks == [range, second])
    }

    @Test("選び始めたところが同じあいだは、プレビューを送り直さない")
    func dragDoesNotRescroll() {
        var link = SelectionLink()
        link.editorSelectionChanged([NSRange(location: 10, length: 2)], line: 3)
        let first = link.previewReveal
        link.editorSelectionChanged([NSRange(location: 10, length: 40)], line: 3)
        #expect(link.previewReveal == first)
    }

    @Test("本文が変わったら、両側の色を消す")
    func clearRemovesBoth() {
        var link = SelectionLink()
        link.editorSelectionChanged([range], line: 3)
        link.clear()
        #expect(link.previewMarks.isEmpty)
        #expect(link.editorMarks.isEmpty)
        #expect(link.previewReveal == nil)
    }
}
