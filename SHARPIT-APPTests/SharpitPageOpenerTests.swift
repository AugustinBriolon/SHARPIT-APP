import Foundation
import Testing
@testable import Sharpit

@MainActor
@Suite(.serialized)
struct SharpitPageOpenerTests {
    @Test func aPageAskedBeforeTheAppIsReadyIsOpenedOnceItIs() {
        let saved = SharpitPageOpener.open
        defer { if let saved { SharpitPageOpener.register(saved) } }
        SharpitPageOpener.open = nil
        let coach = URL(string: "https://sharpit.app/coach")!
        SharpitPageOpener.request(coach)
        #expect(SharpitPageOpener.pending == coach)

        var opened: [URL] = []
        SharpitPageOpener.register { opened.append($0) }
        #expect(opened == [coach])
        #expect(SharpitPageOpener.pending == nil)

        SharpitPageOpener.request(URL(string: "https://sharpit.app/nutrition/scan")!)
        #expect(opened.count == 2)
    }

    @Test func theControlsOpenPagesTheAppReads() {
        for path in ["/coach", "/nutrition/scan"] {
            #expect(IncomingLink.parse(URL(string: "https://sharpit.app\(path)")!) != nil)
        }
    }
}
