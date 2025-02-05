/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import RxSwift
import RxRelay
import MozillaAppServices
import SwiftKeychainWrapper
import WebKit

/* These UserDefault keys are maintained separately from the `UserDefaultKey`
 * enum in BaseConstants.swift because, for the time being, they are only
 * useful in the main application. However, rather than maintaining two
 * separate UserDefaults instances, all the values for these keys are stored
 * in the app group instance so that no further migrations will be required
 * in the case that they become relevant in an app extension context. */
enum LocalUserDefaultKey: String {
    case preferredBrowser, recordUsageData, appVersionCode

    static var allValues: [LocalUserDefaultKey] = [.preferredBrowser, .recordUsageData, .appVersionCode]

    var defaultValue: Any? {
        switch self {
        case .preferredBrowser:
            return Constant.setting.defaultPreferredBrowser.rawValue
        case .recordUsageData:
            return Constant.setting.defaultRecordUsageData
        case .appVersionCode:
            return 0
        }
    }
}

class AccountStore: BaseAccountStore {
    static let shared = AccountStore()

    private let urlCache: URLCache
    private let webData: WKWebsiteDataStore
    private let disposeBag = DisposeBag()

    private var _loginURL = ReplaySubject<URL>.create(bufferSize: 1)
    private var _oldAccountPresence = BehaviorRelay<Bool>(value: false)

    public var loginURL: Observable<URL> {
        return _loginURL.asObservable()
    }

    public var hasOldAccountInformation: Observable<Bool> {
        return _oldAccountPresence.asObservable()
    }

    private var generatedLoginURL: Observable<URL> {
        return Observable.create( { observer -> Disposable in
            self.fxa?.beginOAuthFlow(scopes: Constant.fxa.scopes) { url, err in
                if let err = err {
                    observer.onError(err)
                }
                if let url = url {
                    observer.onNext(url)
                }
            }

            return Disposables.create()
        })
    }

    init(dispatcher: Dispatcher = Dispatcher.shared,
         networkStore: NetworkStore = NetworkStore.shared,
         keychainWrapper: KeychainWrapper = KeychainWrapper.sharedAppContainerKeychain,
         urlCache: URLCache = URLCache.shared,
         webData: WKWebsiteDataStore = WKWebsiteDataStore.default()
        ) {
        self.urlCache = urlCache
        self.webData = webData

        super.init(dispatcher: dispatcher, keychainWrapper: keychainWrapper, networkStore: networkStore)
    }

    override func initialized() {
        self.dispatcher.register
                .filterByType(class: AccountAction.self)
                .subscribe(onNext: { action in
                    switch action {
                    case .oauthRedirect(let url):
                        self.oauthLogin(url)
                    case .clear:
                        self.clear()
                    case .oauthSignInMessageRead:
                        self.clearOldKeychainValues()
                    }
                })
                .disposed(by: self.disposeBag)

        self.dispatcher.register
                .filterByType(class: LifecycleAction.self)
                .subscribe(onNext: { [weak self] action in
                    guard case let .upgrade(previous, _) = action else {
                        return
                    }

                    if previous <= 1 {
                        self?._syncCredentials.onNext(nil)
                        self?._profile.onNext(nil)
                        self?._oldAccountPresence.accept(true)
                    }
                })
                .disposed(by: self.disposeBag)

        initFxa()
    }
}

extension AccountStore {
    private func initFxa() {
        if let accountJSON = self.storedAccountJSON {
            self.fxa = try? FirefoxAccount.fromJSON(state: accountJSON)
            self.generateLoginURL()
            self.populateAccountInformation(false)
        } else {
            let config = FxAConfig.release(clientId: Constant.fxa.clientID, redirectUri: Constant.fxa.redirectURI)

            self.fxa = try? FirefoxAccount(config: config)
            self.generateLoginURL()

            self._syncCredentials.onNext(nil)
            self._profile.onNext(nil)
        }
    }

    private func generateLoginURL() {
        self.networkStore.connectedToNetwork
            .distinctUntilChanged()
            // don't try to generate the URL unless we're connected to the internet
            .filter { $0 }
            // only generate the login URL once per call to this method
            .take(1)
            .flatMap { _ in self.generatedLoginURL }
            .bind(to: self._loginURL)
            .disposed(by: self.disposeBag)
    }

    private func clear() {
        for identifier in KeychainKey.allValues {
            _ = self.keychainWrapper.removeObject(forKey: identifier.rawValue)
        }

        self.webData.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            self.webData.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records) { }
        }

        self.urlCache.removeAllCachedResponses()

        self._profile.onNext(nil)
        self._syncCredentials.onNext(nil)

        self.initFxa()
    }

    private func clearOldKeychainValues() {
        for identifier in KeychainKey.oldAccountValues {
            _ = KeychainWrapper.standard.removeObject(forKey: identifier.rawValue)
        }

        self.webData.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            self.webData.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records) { }
        }

        self._oldAccountPresence.accept(false)
    }

    private func oauthLogin(_ navigationURL: URL) {
        guard let components = URLComponents(url: navigationURL, resolvingAgainstBaseURL: true),
              let queryItems = components.queryItems else {
            return
        }

        var dic = [String: String]()
        queryItems.forEach {
            dic[$0.name] = $0.value
        }

        guard let code = dic["code"],
              let state = dic["state"] else {
            return
        }

        self.fxa?.completeOAuthFlow(code: code, state: state) { [weak self] (_, err) in
            guard err == nil else {
                print(err.debugDescription)
                return
            }
            self?.populateAccountInformation(true)
        }
    }
}
