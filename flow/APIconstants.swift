//
//  APIconstants.swift
//  flow
//
//  Created by Drew Visconti on 1/14/26.
//

import Foundation

enum APIconstants {
    static let apiHost = "api.spotify.com"
    static let authHost = "accounts.spotify.com"
    static let clientID = "5477354bc87a4af1b2b8b10e23998f8d"
    static let clientSecret = "124885a709a44f5b9f4c251458e19a22"
    static let redirectURI = "http://127.0.0.1:3000/callback"
    static let sp_dc = "AQDC2OHZEwmBLgftlha5WQsaIkOUlh06pXk3kteqE3dMycyAKVr9D3xBiGW3rpe2cxdD28nC0mscM2-WmplBZCa1IXnQzUCQf_0aF-y9y4_Tjwd26_BRcmYhrHpXcc1ibxaad3kqsP3z0WN6SSy5m9YqASdd6cvlDndSjwShqm_zzPwtNslNx2LOGCxYYrX9yQGNkF_xUP71X0oG6lo"
    static let responseType = "code"
    static let scopes = "user-read-playback-state user-read-currently-playing"
    
    static var authParams = [
        "response_type": responseType,
        "client_id": clientID,
        "redirect_uri": redirectURI,
        "scope": scopes
    ]
}
