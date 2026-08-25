import XCTest
@testable import RaTamerCore

final class ActionCatalogTests: XCTestCase {
    func testAllActionsCoversSystemCatalog() {
        for action in ActionCatalog.allActions {
            XCTAssertFalse(ActionCatalog.title(for: action).isEmpty)
        }
        XCTAssertTrue(ActionCatalog.allActions.contains(.cycleDPI))
        XCTAssertTrue(ActionCatalog.allActions.contains(.click(button: 3)))
        XCTAssertTrue(ActionCatalog.allActions.contains(.click(button: 4)))
    }
}
