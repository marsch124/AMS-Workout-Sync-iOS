import XCTest

/*
 * Favourite sessions and Repeat, found by identifier only (invented favourites,
 * the test plan). Written to compile; not run here.
 */
final class FavouritesUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func launch(_ switchName: String) -> XCUIApplication {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launchEnvironment[switchName] = "1"
        app.launch()
        return app
    }

    func testTheSettingsPageListsThreeFavouritesWithHandles() {
        let app = launch("AMSWS_FAVOURITES_PAGE")
        XCTAssertTrue(any(app, "favourite-row-0").waitForExistence(timeout: 15), "no first favourite")
        XCTAssertTrue(any(app, "favourite-row-2").exists, "three favourites were expected")
        XCTAssertTrue(any(app, "favourite-handle-0").exists, "no handle to drag")
        any(app, "favourite-remove-0").tap()
        XCTAssertTrue(app.buttons["Keep it"].waitForExistence(timeout: 5), "no question before removing")
    }

    func testTheAddPageShowsTheFavouritesBlockAndATapFillsTheTitle() {
        let app = launch("AMSWS_ADD_WITH_FAVOURITES")
        XCTAssertTrue(any(app, "favourites-block").waitForExistence(timeout: 15), "no favourites block")
        any(app, "favourite-tile-1").tap()
        XCTAssertEqual(app.textFields["edit-title"].value as? String, "Easy run")
    }

    func testTheRepeatRowListsTheDaysThatWillBeAdded() {
        let app = launch("AMSWS_REPEAT")
        XCTAssertTrue(any(app, "repeat-row").waitForExistence(timeout: 15), "no Repeat row")
        XCTAssertTrue(any(app, "repeat-until").exists, "no date to repeat until")
        XCTAssertTrue(any(app, "repeat-list").exists, "no list of days")
    }
}
