//
//  FairplaySessionManager.swift
//
//
//  Created by Emily Dixon on 4/19/24.
//

import Foundation
import AVFoundation

class FairplaySessionManager {
    
    private var playbackOptionsByPlaybackID: [String: PlaybackOptions] = [:]
    // note - null on simulators or other environments where fairplay isn't supported
    private let contentKeySession: AVContentKeySession?
    private let sessionDelegate: AVContentKeySessionDelegate?
    
    private let urlSession = URLSession.shared
    
    func addContentKeyRecipient(_ recipient: AVContentKeyRecipient) {
        contentKeySession?.addContentKeyRecipient(recipient)
    }
    
    func removeContentKeyRecipient(_ recipient: AVContentKeyRecipient) {
        contentKeySession?.removeContentKeyRecipient(recipient)
    }
    
    // MARK: Requesting licenses and certs
    
    /// Requests the App Certificate for a playback id
    func requestCertificate(playbackID: String, drmToken: String, completion: (Result<Data, Error>) -> Void) {
        // todo - request app certficate from the backend
        let tempCert = ProcessInfo.processInfo.environment["APP_CERT_BASE64"]
        //print("CERTIFICATE :: temp app cert is \(tempCert)")
        
        guard let tempCert = tempCert else {
            completion(Result.failure(CancellationError())) // todo - a real Error type
            return
        }
        
        let certData = Data(base64Encoded: tempCert, options: Data.Base64DecodingOptions.ignoreUnknownCharacters)!
        print("CERTIFICATE :: Delivering App Certificate")
        completion(Result.success(certData))
    }
    
    /// Requests a license to play based on the given SPC data
    /// - parameter playbackDomain - Domain for the playback URL, (eg, stream.mux.com or a custom domain)
    /// - parameter offline - Not currently used, may not ever be used in short-term, maybe delete?
    func requestLicense(
        spcData: Data,
        playbackID: String,
        drmToken: String,
        playbackDomain: String,
        offline _: Bool,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        // no need to track license request tasks since we are not prewarming
        //  and therefore don't need to worry about re-joinining any existing
        //  license reqs.
        
        // TODO: Need to calculate license Domain from input playbackDomain
        //  ie, stream.mux.com -> license.mux.com or custom.domain.com -> TODO: ????
        let licenseDomain = "license.gcp-us-west1-vos1.staging.mux.com"
        
        var request = URLRequest(url: licenseURL(playbackId: playbackID, drmToken: drmToken, licenseDomain: licenseDomain))
        
        // NOTE: The format of this POST body is likely to change before release. Instead of accepting
        //  this form-encoded body, a subsequent change will require only the Base64 SPC
        // BODY PARAMS
        // Base-64 the SPC, urlencode that, prepare form-encoded body with spc
        let encodedSpcMessage = urlEncodeBase64(spcData.base64EncodedString())
        print("Raw (non-percent encoded) SPC base64:", spcData.base64EncodedString()) // we dump the encoded version too
        var postData = String(format: "spc=%@", encodedSpcMessage)
        // DRMToday example appends `offline` to POST body, but we are not doing offline keys yet
        //  also, we don't like the form-encoded POST body

        
        request.httpMethod = "POST"
//        print("POST BODY: \(postData)")
        //request.httpBody = postData.data(using: .utf8, allowLossyConversion: true)
        request.httpBody = spcData

        
        // QUERY PARAMS
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(String(format: "%lu", request.httpBody?.count ?? 0), forHTTPHeaderField: "Content-Length")
        print("Sending License/CKC Request to: \(request.url?.absoluteString)")
        print("\t with header fields: \(request.allHTTPHeaderFields)")

        let task = urlSession.dataTask(with: request) { [completion] data, response, error in
            print("<><> GOT LICENSE RESPONSE")
            var responseCode: Int? = nil
            if let httpResponse = response as? HTTPURLResponse {
                responseCode = httpResponse.statusCode
                print("License response code: \(httpResponse.statusCode)")
                print("License response headers: ", httpResponse.allHeaderFields)

            }
            // error case: I/O finished with non-successful response
            guard responseCode == 200 else {
                print("CKC request failed: \(responseCode)")
                completion(Result.failure(TempError()))
                return
            }
            // error case: I/O failed
            if let error = error {
                print("URL Session Task Failed: \(error.localizedDescription)")
                completion(Result.failure(error)) // todo - real Error type
                return
            }
            // strange edge case: 200 with no response body
            //  this happened because of a client-side encoding difference causing an error
            //  with our drm vendor and probably shouldn't be relevant, but lets not crash
            guard let data = data else {
                print("No CKC data despite server returning success")
                completion(Result.failure(TempError())) // todo - real Error type
                return
            }
            
            let responseBody = data.base64EncodedString()
            print("License response body: ", responseBody)

            let ckcData = data
                let ckcMessage = Data(base64Encoded: ckcData)
                
                // TODO: um do not in fact log the CKC
                // Also log the CKC
                //let ckcBase64 = ckcData.base64EncodedString()
//                let ckcBase64 = ckcMessage!.base64EncodedString()
//                print("CKC Response Body base64:", ckcBase64)
                print("")

                //completion(Result.success(ckcData))
                completion(Result.success(ckcMessage!))
            }
        task.resume()
    }
    
    // MARK: registering assets
    
    /// Registers a ``PlaybackOptions`` for DRM playback, associated with the given playbackID
    func registerPlaybackOptions(_ opts: PlaybackOptions, for playbackID: String) {
        print("Registering playbackID \(playbackID)")
        playbackOptionsByPlaybackID[playbackID] = opts
    }
    
    /// Gets a DRM token previously registered via ``registerPlaybackOptions``
    func findRegisteredPlaybackOptions(for playbackID: String) -> PlaybackOptions? {
        print("Finding playbackID \(playbackID)")
        return playbackOptionsByPlaybackID[playbackID]
    }
    
    /// Unregisters a ``PlaybackOptions`` for DRM playback, given the assiciated playback ID
    func unregisterPlaybackOptions(for playbackID: String) {
        print("UN-Registering playbackID \(playbackID)")
        playbackOptionsByPlaybackID.removeValue(forKey: playbackID)
    }
    
    // MARK: helpers
    
    private func licenseURL(playbackId: String, drmToken: String, licenseDomain: String) -> URL {
        let baseStr = "https://\(licenseDomain)/license/fairplay/\(playbackId)?token=\(drmToken)"
        let url = URL(string: baseStr)
        return url!
    }
    
    /// URL-encodes base-64 data, encoding these characters: `:?=&+`
    ///  This function (probably) isn't appropriate for general URL-encoding.
    ///  it's just for base64, just for license/cert requests
    private func urlEncodeBase64(_ value: String?) -> String {
        let queryKeyValueString = CharacterSet(charactersIn: ":?=&+").inverted
        return value?.addingPercentEncoding(withAllowedCharacters: queryKeyValueString) ?? ""
    }
    
    // MARK: initializers
    
    convenience init() {
#if targetEnvironment(simulator)
        let session: AVContentKeySession? = nil
        let delegate: AVContentKeySessionDelegate? = nil
#else
        let session = AVContentKeySession(keySystem: .fairPlayStreaming)
        let delegate = ContentKeySessionDelegate()
#endif
        
        self.init(
            contentKeySession: session,
            sessionDelegate: delegate,
            sessionDelegateQueue: DispatchQueue(label: "com.mux.player.fairplay")
        )
    }
    
    init(
        contentKeySession: AVContentKeySession?,
        sessionDelegate: AVContentKeySessionDelegate?,
        sessionDelegateQueue: DispatchQueue
    ) {
//        print(">>>>>>>>>>>>>>>>>")
//        print(ProcessInfo.processInfo.environment["APP_CERT_BASE64"])
        
        contentKeySession?.setDelegate(sessionDelegate, queue: sessionDelegateQueue)
        
        self.contentKeySession = contentKeySession
        self.sessionDelegate = sessionDelegate
    }
}


// TODO: Final implementation needs something more verbose
class TempError: Error {
}
