import XCTest
@testable import RatTamerCore

final class DPICycleTests: XCTestCase {
    func testNextAdvancesThroughPresetsWithWrapAround() {
        let presets: [UInt16] = [1000, 1600, 2000, 4000]
        XCTAssertEqual(DPICycle.next(current: 1000, presets: presets), 1600)
        XCTAssertEqual(DPICycle.next(current: 1600, presets: presets), 2000)
        XCTAssertEqual(DPICycle.next(current: 2000, presets: presets), 4000)
        XCTAssertEqual(DPICycle.next(current: 4000, presets: presets), 1000)
    }

    func testNextReturnsFirstPresetWhenCurrentNotInList() {
        XCTAssertEqual(DPICycle.next(current: 1200, presets: [1000, 2000]), 1000)
    }

    func testNextWithSinglePresetReturnsSameValue() {
        XCTAssertEqual(DPICycle.next(current: 1000, presets: [1000]), 1000)
        XCTAssertEqual(DPICycle.next(current: 3000, presets: [1000]), 1000)
    }

    func testNextWithEmptyPresetsReturnsNil() {
        XCTAssertNil(DPICycle.next(current: 1000, presets: []))
    }

    func testDefaultPresetsAreWithinDeviceRange() {
        XCTAssertEqual(DPICycle.defaultPresets.count, 4)
        XCTAssertTrue(DPICycle.defaultPresets.allSatisfy { $0 >= 200 && $0 <= 4000 })
    }

    func testRecommendedPresetsFallsBackToDefaultsWhenEmpty() {
        XCTAssertEqual(DPICycle.recommendedPresets(from: []), DPICycle.defaultPresets)
    }

    func testRecommendedPresetsReturnsSortedUniqueValuesWhenWithinLimit() {
        XCTAssertEqual(DPICycle.recommendedPresets(from: [1600, 1000, 2000, 1000]),
                       [1000, 1600, 2000])
    }

    func testRecommendedPresetsKeepsMinAndMaxWhenSampling() {
        let dense = Array(stride(from: 200, through: 4000, by: 200)).map { UInt16($0) }
        let presets = DPICycle.recommendedPresets(from: dense)
        XCTAssertEqual(presets.count, 4)
        XCTAssertEqual(presets.first, 200)
        XCTAssertEqual(presets.last, 4000)
        XCTAssertEqual(presets, presets.sorted())
    }

    func testRecommendedPresetsLimitIsRespected() {
        let presets = DPICycle.recommendedPresets(from: [100, 300, 600, 900, 1200], limit: 3)
        XCTAssertEqual(presets.count, 3)
        XCTAssertEqual(presets.first, 100)
        XCTAssertEqual(presets.last, 1200)
    }
}
