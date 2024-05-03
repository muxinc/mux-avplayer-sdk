//
//  FairPlaySessionManagerTests.swift
//
//
//  Created by Emily Dixon on 5/2/24.
//

import Foundation
import XCTest
import AVKit
@testable import MuxPlayerSwift

class FairPlaySessionManagerTests : XCTestCase {
    
    // mocks
    private var mockURLSession: URLSession!
    private var mockAVContentKeySession: DummyAVContentKeySession!
    
    // object under test
    private var sessionManager: FairPlaySessionManager!
    
    override func setUp() {
        super.setUp()
        
        let mockURLSessionConfig = URLSessionConfiguration.default
        mockURLSessionConfig.protocolClasses = [MockURLProtocol.self]
        self.mockURLSession = URLSession.init(configuration: mockURLSessionConfig)
        
        self.mockAVContentKeySession =  DummyAVContentKeySession(keySystem: .clearKey)
        self.sessionManager = DefaultFPSSManager(
            // .clearKey is used because .fairPlay requires a physical device
            contentKeySession: mockAVContentKeySession,
            sessionDelegate: DummyAVContentKeySessionDelegate(),
            sessionDelegateQueue: DispatchQueue(label: "com.mux.player.test.fairplay"),
            urlSession: mockURLSession
        )
    }
    
    // Also tests PlaybackOptions.rootDomain
    func testMakeLicenseDomain() throws {
        let optionsWithoutCustomDomain = PlaybackOptions()
        let defaultLicenseDomain = DefaultFPSSManager.makeLicenseDomain(optionsWithoutCustomDomain.rootDomain())
        XCTAssert(
            defaultLicenseDomain == "license.mux.com",
            "Default license server is license.mux.com"
        )
        
        var optionsCustomDomain = PlaybackOptions()
        optionsCustomDomain.customDomain = "fake.custom.domain.xyz"
        let customLicenseDomain = DefaultFPSSManager.makeLicenseDomain(optionsCustomDomain.rootDomain())
        XCTAssert(
            customLicenseDomain == "license.fake.custom.domain.xyz",
            "Custom license server is license.fake.custom.domain.xyz"
        )
    }
    
    func testMakeLicenseURL() throws {
        let fakePlaybackId = "fake_playback_id"
        let fakeDrmToken = "fake_drm_token"
        let fakeLicenseDomain = "license.fake.domain.xyz"
        
        let licenseURL = DefaultFPSSManager.makeLicenseURL(
            playbackID: fakePlaybackId,
            drmToken: fakeDrmToken,
            licenseDomain: fakeLicenseDomain
        )
        let expected = "https://\(fakeLicenseDomain)/license/fairplay/\(fakePlaybackId)?token=\(fakeDrmToken)"
        
        XCTAssertEqual(
            expected, licenseURL.absoluteString
        )
    }
    
    func testMakeAppCertificateUrl() throws {
        let fakePlaybackId = "fake_playback_id"
        let fakeDrmToken = "fake_drm_token"
        let fakeLicenseDomain = "license.fake.domain.xyz"
        
        let licenseURL = DefaultFPSSManager.makeAppCertificateURL(
            playbackID: fakePlaybackId,
            drmToken: fakeDrmToken,
            licenseDomain: fakeLicenseDomain
        )
        let expected = "https://\(fakeLicenseDomain)/appcert/fairplay/\(fakePlaybackId)?token=\(fakeDrmToken)"
        
        XCTAssertEqual(
            expected, licenseURL.absoluteString
        )
    }
    
    func testRequestCertificateSuccess() throws {
        let fakeRootDomain = "custom.domain.com"
        let fakePlaybackId = "fake_playback_id"
        let fakeDrmToken = "fake_drm_token"
        // real app certs are opaque binary to us, the fake one can be whatever
        let fakeAppCert = "fake-application-cert-binary-data".data(using: .utf8)
        
        let requestSuccess = XCTestExpectation(description: "request certificate successfully")
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            
            return (response, fakeAppCert)
        }
        
        var foundAppCert: Data?
        sessionManager.requestCertificate(
            fromDomain: fakeRootDomain,
            playbackID: fakePlaybackId,
            drmToken: fakeDrmToken
        ) { result in
            guard let result = try? result.get() else {
                XCTFail("Incorrect status code")
                return
            }
            
            foundAppCert = result
            requestSuccess.fulfill()
        }
        wait(for: [requestSuccess])
        XCTAssertEqual(foundAppCert, fakeAppCert)
    }
}
