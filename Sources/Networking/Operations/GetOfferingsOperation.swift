//
//  Copyright RevenueCat Inc. All Rights Reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      https://opensource.org/licenses/MIT
//
//  GetOfferingsOperation.swift
//
//  Created by Joshua Liebowitz on 11/19/21.

import Foundation

class GetOfferingsOperation: CacheableNetworkOperation {

    private let offeringsCallbackCache: CallbackCache<OfferingsCallback>
    private let configuration: AppUserConfiguration

    init(configuration: UserSpecificConfiguration,
         offeringsCallbackCache: CallbackCache<OfferingsCallback>) {
        self.configuration = configuration
        self.offeringsCallbackCache = offeringsCallbackCache

        super.init(configuration: configuration, individualizedCacheKeyPart: configuration.appUserID)
    }

    override func begin(completion: @escaping () -> Void) {
        self.getOfferings(completion: completion)
    }

}

private extension GetOfferingsOperation {

    func getOfferings(completion: @escaping () -> Void) {
        guard let appUserID = try? configuration.appUserID.escapedOrError() else {
            self.offeringsCallbackCache.performOnAllItemsAndRemoveFromCache(withCacheable: self) { callback in
                callback.completion(.failure(ErrorUtils.missingAppUserIDError()))
            }
            completion()

            return
        }

        let request = HTTPRequest(method: .get, path: .getOfferings(appUserID: appUserID))

        httpClient.perform(request, authHeaders: self.authHeaders) { statusCode, result in
            defer {
                completion()
            }

            let parsedResponse: Result<[String: Any], Error> = result
                .mapError { ErrorUtils.networkError(withUnderlyingError: $0) }
                .flatMap { response in
                    return statusCode.isSuccessfulResponse
                    ? .success(response)
                    : .failure(
                        ErrorUtils.backendError(withBackendCode: BackendErrorCode(code: response["code"]),
                                                backendMessage: response["message"] as? String)
                    )
                }

            self.offeringsCallbackCache.performOnAllItemsAndRemoveFromCache(withCacheable: self) { callbackObject in
                callbackObject.completion(parsedResponse)
            }
        }
    }

}
