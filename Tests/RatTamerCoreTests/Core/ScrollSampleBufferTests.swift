import XCTest
@testable import RatTamerCore

final class ScrollSampleBufferTests: XCTestCase {
    private func sample(_ offset: TimeInterval, value: Double, kind: ScrollSample.Kind = .raw) -> ScrollSample {
        ScrollSample(time: Date(timeIntervalSince1970: 1000 + offset), kind: kind, value: value)
    }

    func testWindowOrdersByTime() {
        let buffer = ScrollSampleBuffer()
        buffer.append(sample(0.3, value: 10))
        buffer.append(sample(0.1, value: 5))
        buffer.append(sample(0.2, value: 7, kind: .output))
        let got = buffer.samples(in: 5, before: Date(timeIntervalSince1970: 1000.5))
        XCTAssertEqual(got.map { $0.value }, [5, 7, 10])
        XCTAssertEqual(got.map { $0.kind }, [.raw, .output, .raw])
    }

    func testExcludesOutOfWindowAndFuture() {
        let buffer = ScrollSampleBuffer()
        buffer.append(sample(-10, value: 1))       // mais antiga que a janela
        buffer.append(sample(-4.9, value: 2))      // dentro
        buffer.append(sample(6.0, value: 3))       // no futuro
        let got = buffer.samples(in: 5, before: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(got.map { $0.value }, [2])
    }

    func testCapacityTrimsOldest() {
        let buffer = ScrollSampleBuffer(capacity: 3)
        for i in 0..<5 {
            buffer.append(sample(Double(i), value: Double(i)))
        }
        let got = buffer.samples(in: 100, before: Date(timeIntervalSince1970: 1100))
        XCTAssertEqual(got.map { $0.value }, [2, 3, 4])
    }

    func testAppendAndSnapshotFromDifferentThreads() {
        let buffer = ScrollSampleBuffer()
        let group = DispatchGroup()
        for thread in 0..<4 {
            group.enter()
            DispatchQueue.global().async {
                for i in 0..<50 {
                    buffer.append(self.sample(Double(thread * 1000 + i), value: Double(i)))
                }
                group.leave()
            }
        }
        group.wait()
        let got = buffer.samples(in: 100000, before: Date(timeIntervalSince1970: 100000))
        XCTAssertEqual(got.count, 200)
    }
}
