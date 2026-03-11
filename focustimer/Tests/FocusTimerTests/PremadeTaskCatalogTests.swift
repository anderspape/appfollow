import XCTest
@testable import FocusTimer

final class PremadeTaskCatalogTests: XCTestCase {
    func testCatalogLoadsPremadeTemplatesWithCategories() {
        let catalog = PremadeTaskCatalog()
        let templates = catalog.load()

        XCTAssertFalse(templates.isEmpty)
        XCTAssertTrue(templates.allSatisfy { $0.source == .premade })
        XCTAssertTrue(templates.allSatisfy { $0.resolvedCategoryName != nil })
        XCTAssertTrue(templates.allSatisfy { !($0.premadeTemplateID ?? "").isEmpty })

        let grouped = Dictionary(grouping: templates) { $0.resolvedCategoryName ?? "" }
        for category in SessionCategory.all {
            XCTAssertEqual(
                grouped[category.name]?.count,
                10,
                "Expected 10 premade templates for category \(category.name)"
            )
        }
    }
}
