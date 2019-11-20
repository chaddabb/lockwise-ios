/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
// swiftlint:disable line_length
// swiftlint:disable force_cast

import Quick
import Nimble
import WebKit
import RxTest
import RxSwift
import MozillaAppServices

@testable import Lockbox

class DataStoreActionSpec: QuickSpec {
    class FakeDispatcher: Dispatcher {
        var actionArgument: Action?

        override func dispatch(action: Action) {
            self.actionArgument = action
        }
    }

    var dispatcher: FakeDispatcher!
    private let dataStoreName: String = "dstore"
    private let scheduler = TestScheduler(initialClock: 0)
    private let disposeBag = DisposeBag()

    override func spec() {
        describe("Action equality") {
            it("initialize is always equal") {
                // tricky to test because we cannot construct FxAClient.OAuthInfo
            }

            it("non-associated data enum values are always equal") {
                expect(DataStoreAction.lock).to(equal(DataStoreAction.lock))
                expect(DataStoreAction.unlock).to(equal(DataStoreAction.unlock))
                expect(DataStoreAction.reset).to(equal(DataStoreAction.reset))
                expect(DataStoreAction.syncStart).to(equal(DataStoreAction.syncStart))
                expect(DataStoreAction.syncTimeout).to(equal(DataStoreAction.syncTimeout))
            }

            it("touch is equal based on IDs") {
                expect(DataStoreAction.touch(id: "meow")).to(equal(DataStoreAction.touch(id: "meow")))
                expect(DataStoreAction.touch(id: "meow")).notTo(equal(DataStoreAction.touch(id: "woof")))
            }

            it("different enum types are never equal") {
                expect(DataStoreAction.unlock).notTo(equal(DataStoreAction.lock))
                expect(DataStoreAction.lock).notTo(equal(DataStoreAction.unlock))
                expect(DataStoreAction.syncStart).notTo(equal(DataStoreAction.reset))
                expect(DataStoreAction.reset).notTo(equal(DataStoreAction.syncStart))
            }

            it("update login equal based on logins") {
                let login1 = LoginRecord(fromJSONDict: ["id": "id1", "hostname": "https://www.mozilla.com", "username": "asdf", "password": ""])
                let login2 = LoginRecord(fromJSONDict: ["id": "id2", "hostname": "https://www.getfirefox.com", "username": "asdf", "password": ""])
                expect(DataStoreAction.update(login: login1)).to(equal(DataStoreAction.update(login: login1)))
                expect(DataStoreAction.update(login: login1)).notTo(equal(DataStoreAction.update(login: login2)))
            }
            it("syncError are equal based onerror") {
                expect(DataStoreAction.syncError(error: "asdf")).to(equal(DataStoreAction.syncError(error: "asdf")))
                expect(DataStoreAction.syncError(error: "asdf")).notTo(equal(DataStoreAction.syncError(error: "fdsa")))
            }

        }
    }
}
