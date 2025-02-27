//
//  BackendIntegrationTests.swift
//  BackendIntegrationTests
//
//  Created by Andrés Boedo on 5/3/21.
//  Copyright © 2021 Purchases. All rights reserved.
//

import Nimble
import RevenueCat
import StoreKitTest
import XCTest

class TestPurchaseDelegate: NSObject, PurchasesDelegate {

    var customerInfo: CustomerInfo?
    var customerInfoUpdateCount = 0

    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        self.customerInfo = customerInfo
        customerInfoUpdateCount += 1
    }

}

class BackendIntegrationSK2Tests: BackendIntegrationSK1Tests {

    override class var sk2Enabled: Bool { return true }

}

class BackendIntegrationSK1Tests: XCTestCase {

    private var testSession: SKTestSession!
    private var userDefaults: UserDefaults!
    // swiftlint:disable:next weak_delegate
    private var purchasesDelegate: TestPurchaseDelegate!

    class var sk2Enabled: Bool { return false }

    private static let timeout: DispatchTimeInterval = .seconds(10)

    override func setUpWithError() throws {
        try super.setUpWithError()

        guard Constants.apiKey != "REVENUECAT_API_KEY", Constants.proxyURL != "REVENUECAT_PROXY_URL" else {
            XCTFail("Must set configuration in `Constants.swift`")
            throw ErrorCode.configurationError
        }

        testSession = try SKTestSession(configurationFileNamed: Constants.storeKitConfigFileName)
        testSession.resetToDefaultState()
        testSession.disableDialogs = true
        testSession.clearTransactions()

        userDefaults = UserDefaults(suiteName: Constants.userDefaultsSuiteName)
        userDefaults?.removePersistentDomain(forName: Constants.userDefaultsSuiteName)
        if !Constants.proxyURL.isEmpty {
            Purchases.proxyURL = URL(string: Constants.proxyURL)
        }

        configurePurchases()
    }

    func testCanGetOfferings() async throws {
        let receivedOfferings = try await Purchases.shared.offerings()
        expect(receivedOfferings.all).toNot(beEmpty())
    }

    func testCanMakePurchase() async throws {
        try await self.purchaseMonthlyOffering()

        try self.verifyEntitlementWentThrough()
        let entitlements = self.purchasesDelegate.customerInfo?.entitlements
        expect(entitlements?[Self.entitlementIdentifier]?.isActive) == true
    }

    func testPurchaseMadeBeforeLogInIsRetainedAfter() async throws {
        let customerInfo = try await self.purchaseMonthlyOffering().customerInfo
        expect(customerInfo.entitlements.all.count) == 1

        let entitlements = self.purchasesDelegate.customerInfo?.entitlements
        expect(entitlements?[Self.entitlementIdentifier]?.isActive) == true

        let anonUserID = Purchases.shared.appUserID
        let identifiedUserID = "\(#function)_\(anonUserID)_".replacingOccurrences(of: "RCAnonymous", with: "")

        let (identifiedCustomerInfo, created) = try await Purchases.shared.logIn(identifiedUserID)
        expect(created) == true
        expect(identifiedCustomerInfo.entitlements[Self.entitlementIdentifier]?.isActive) == true
    }

    func testPurchaseMadeBeforeLogInWithExistingUserIsNotRetainedUnlessRestoreCalled() async throws {
        let existingUserID = "\(#function)\(UUID().uuidString)"
        try await self.waitUntilCustomerInfoIsUpdated()

        // log in to create the user, then log out
        _ = try await Purchases.shared.logIn(existingUserID)
        _ = try await Purchases.shared.logOut()

        // purchase as anonymous user, then log in
        try await self.purchaseMonthlyOffering()
        try self.verifyEntitlementWentThrough()

        let (customerInfo, created) = try await Purchases.shared.logIn(existingUserID)
        self.assertNoPurchases(customerInfo)
        expect(created) == false

        _ = try await Purchases.shared.restorePurchases()

        try self.verifyEntitlementWentThrough()
    }

    func testPurchaseAsIdentifiedThenLogOutThenRestoreGrantsEntitlements() async throws {
        let existingUserID = UUID().uuidString
        try await self.waitUntilCustomerInfoIsUpdated()

        _ = try await Purchases.shared.logIn(existingUserID)
        try await self.purchaseMonthlyOffering()

        try self.verifyEntitlementWentThrough()

        let customerInfo = try await Purchases.shared.logOut()
        self.assertNoPurchases(customerInfo)

        _ = try await Purchases.shared.restorePurchases()

        try self.verifyEntitlementWentThrough()
    }

    func testPurchaseWithAskToBuyPostsReceipt() async throws {
        try await self.waitUntilCustomerInfoIsUpdated()

        // `SKTestSession` ignores the override done by `Purchases.simulatesAskToBuyInSandbox = true`
        self.testSession.askToBuyEnabled = true

        let customerInfo = try await Purchases.shared.logIn(UUID().uuidString).customerInfo

        do {
            try await self.purchaseMonthlyOffering()
            XCTFail("Expected payment to be deferred")
        } catch ErrorCode.paymentPendingError { /* Expected error */ }

        self.assertNoPurchases(customerInfo)

        let transactions = self.testSession.allTransactions()
        expect(transactions).to(haveCount(1))
        let transaction = transactions.first!

        try self.testSession.approveAskToBuyTransaction(identifier: transaction.identifier)

        // This shouldn't throw error anymore
        try await self.purchaseMonthlyOffering()

        try self.verifyEntitlementWentThrough()
    }

    func testLogInReturnsCreatedTrueWhenNewAndFalseWhenExisting() async throws {
        let anonUserID = Purchases.shared.appUserID
        let identifiedUserID = "\(#function)_\(anonUserID)".replacingOccurrences(of: "RCAnonymous", with: "")

        var (_, created) = try await Purchases.shared.logIn(identifiedUserID)
        expect(created) == true

        _ = try await Purchases.shared.logOut()

        (_, created) = try await Purchases.shared.logIn(identifiedUserID)
        expect(created) == false
    }

    func testLogInThenLogInAsAnotherUserWontTransferPurchases() async throws {
        let userID1 = UUID().uuidString
        let userID2 = UUID().uuidString

        _ = try await Purchases.shared.logIn(userID1)
        try await self.purchaseMonthlyOffering()

        try self.verifyEntitlementWentThrough()

        testSession.clearTransactions()

        let (identifiedCustomerInfo, _) = try await Purchases.shared.logIn(userID2)
        self.assertNoPurchases(identifiedCustomerInfo)

        let currentCustomerInfo = try XCTUnwrap(self.purchasesDelegate.customerInfo)

        expect(currentCustomerInfo.originalAppUserId) == userID2
        self.assertNoPurchases(currentCustomerInfo)
    }

    func testLogOutRemovesEntitlements() async throws {
        let anonUserID = Purchases.shared.appUserID
        let identifiedUserID = "identified_\(anonUserID)".replacingOccurrences(of: "RCAnonymous", with: "")

        let (_, created) = try await Purchases.shared.logIn(identifiedUserID)
        expect(created) == true

        try await self.purchaseMonthlyOffering()

        try self.verifyEntitlementWentThrough()

        let loggedOutCustomerInfo = try await Purchases.shared.logOut()
        self.assertNoPurchases(loggedOutCustomerInfo)
    }

    @available(iOS 15.0, tvOS 15.0, macOS 12.0, watchOS 8.0, *)
    func testEligibleForIntroBeforePurchaseAndIneligibleAfter() async throws {
        try AvailabilityChecks.iOS15APIAvailableOrSkipTest()

        let offerings = try await Purchases.shared.offerings()
        let product = try XCTUnwrap(offerings.current?.monthly?.storeProduct)

        var eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(product: product)
        expect(eligibility) == .eligible

        let customerInfo = try await self.purchaseMonthlyOffering().customerInfo

        expect(customerInfo.entitlements.all.count) == 1
        let entitlements = self.purchasesDelegate.customerInfo?.entitlements
        expect(entitlements?[Self.entitlementIdentifier]?.isActive) == true

        let anonUserID = Purchases.shared.appUserID
        let identifiedUserID = "\(#function)_\(anonUserID)_".replacingOccurrences(of: "RCAnonymous", with: "")

        let (identifiedCustomerInfo, created) = try await Purchases.shared.logIn(identifiedUserID)
        expect(created) == true
        expect(identifiedCustomerInfo.entitlements[Self.entitlementIdentifier]?.isActive) == true

        eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(product: product)
        expect(eligibility) == .ineligible
    }

    func testExpireSubscription() async throws {
        let (_, created) = try await Purchases.shared.logIn(UUID().uuidString)
        expect(created) == true

        try await self.purchaseMonthlyOffering()
        _ = try await Purchases.shared.syncPurchases()

        try self.verifyEntitlementWentThrough()

        try await self.testSession.expireSubscription(
            productIdentifier: self.monthlyPackage.storeProduct.productIdentifier
        )

        let info = try await Purchases.shared.syncPurchases()
        self.assertNoActiveSubscription(info)
    }

    func testUserHasNoEligibleOffersByDefault() async throws {
        let (_, created) = try await Purchases.shared.logIn(UUID().uuidString)
        expect(created) == true

        let offerings = try await Purchases.shared.offerings()
        let product = try XCTUnwrap(offerings.current?.monthly?.storeProduct)

        expect(product.discounts).to(haveCount(1))
        expect(product.discounts.first?.offerIdentifier) == "com.revenuecat.monthly_4.99.1_free_week"

        let offers = await product.eligiblePromotionalOffers()
        expect(offers).to(beEmpty())
    }

    @available(iOS 15.2, tvOS 15.2, macOS 12.1, watchOS 8.3, *)
    func testPurchaseWithPromotionalOffer() async throws {
        try AvailabilityChecks.iOS15APIAvailableOrSkipTest()
        try XCTSkipIf(Self.sk2Enabled, "This test is not currently passing on SK2")

        let user = UUID().uuidString

        let (_, created) = try await Purchases.shared.logIn(user)
        expect(created) == true

        let products = await Purchases.shared.products(["com.revenuecat.monthly_4.99.no_intro"])
        let product = try XCTUnwrap(products.first)

        // 1. Purchase subscription

        _ = try await Purchases.shared.purchase(product: product)
        _ = try await Purchases.shared.syncPurchases()

        try self.verifyEntitlementWentThrough()

        // 2. Expire subscription

        try self.testSession.expireSubscription(productIdentifier: product.productIdentifier)

        let info = try await Purchases.shared.syncPurchases()
        self.assertNoActiveSubscription(info)

        // 3. Get eligible offer

        let offers = await product.eligiblePromotionalOffers()
        expect(offers).to(haveCount(1))
        let offer = try XCTUnwrap(offers.first)

        // 4. Purchase with offer

        _ = try await Purchases.shared.purchase(product: product, promotionalOffer: offer)
        _ = try await Purchases.shared.syncPurchases()

        // 5. Verify offer was applied

        let entitlement = try self.verifyEntitlementWentThrough()

        let transactions: [Transaction] = await Transaction
            .currentEntitlements
            .compactMap {
                switch $0 {
                case let .verified(transaction): return transaction
                case .unverified: return nil
                }
            }
            .filter { $0.productID == product.productIdentifier }
            .extractValues()

        expect(transactions).to(haveCount(1))
        let transaction = try XCTUnwrap(transactions.first)

        expect(entitlement.latestPurchaseDate) != entitlement.originalPurchaseDate
        expect(transaction.offerID) == offer.discount.offerIdentifier
        expect(transaction.offerType) == .promotional
    }

}

private extension BackendIntegrationSK1Tests {

    static let entitlementIdentifier = "premium"

    private var monthlyPackage: Package {
        get async throws {
            let offerings = try await Purchases.shared.offerings()
            return try XCTUnwrap(offerings.current?.monthly)
        }
    }

    @discardableResult
    func purchaseMonthlyOffering() async throws -> PurchaseResultData {
        return try await Purchases.shared.purchase(package: self.monthlyPackage)
    }

    func configurePurchases() {
        purchasesDelegate = TestPurchaseDelegate()
        Purchases.configure(withAPIKey: Constants.apiKey,
                            appUserID: nil,
                            observerMode: false,
                            userDefaults: userDefaults,
                            useStoreKit2IfAvailable: Self.sk2Enabled)
        Purchases.logLevel = .debug
        Purchases.shared.delegate = purchasesDelegate
    }

    @discardableResult
    func verifyEntitlementWentThrough() throws -> EntitlementInfo {
        let customerInfo = try XCTUnwrap(self.purchasesDelegate.customerInfo)
        let activeEntitlements = customerInfo.entitlements.active

        expect(activeEntitlements.count) == 1

        return try XCTUnwrap(activeEntitlements[Self.entitlementIdentifier])
    }

    func assertNoActiveSubscription(_ customerInfo: CustomerInfo) {
        expect(customerInfo.entitlements.active).to(beEmpty())
    }

    func assertNoPurchases(_ customerInfo: CustomerInfo) {
        expect(customerInfo.entitlements.all).to(beEmpty())
    }

    @discardableResult
    func waitUntilCustomerInfoIsUpdated() async throws -> CustomerInfo {
        let customerInfo = try await Purchases.shared.customerInfo()
        expect(self.purchasesDelegate.customerInfoUpdateCount) == 1

        return customerInfo
    }

}

extension AsyncSequence {

    func extractValues() async rethrows -> [Element] {
        return try await self.reduce(into: [Element]()) {
            $0 += [$1]
        }
    }

}
