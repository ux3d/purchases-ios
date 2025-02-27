//
//  Copyright RevenueCat Inc. All Rights Reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      https://opensource.org/licenses/MIT
//
//  BackendPostSubscriberAttributesTests.swift
//
//  Created by Nacho Soto on 3/7/22.

import Foundation
import Nimble
import XCTest

@testable import RevenueCat

class BackendPostSubscriberAttributesTests: BaseBackendTests {

    override func createClient() -> MockHTTPClient {
        super.createClient(#file)
    }

    func testPostingWithNoSubscriberAttributesProducesAnError() {
        var eventuallyError: ErrorCode?
        backend.post(subscriberAttributes: [:], appUserID: "testUserID", completion: { error in
            eventuallyError = error as? ErrorCode
        })

        expect(eventuallyError?.codeName).toEventually(equal(ErrorCode.emptySubscriberAttributes.codeName))
    }

}
