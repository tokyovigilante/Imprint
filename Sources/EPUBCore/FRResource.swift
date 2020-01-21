//
//  FRResource.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 29/04/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import Foundation

open class FRResource {
    public var id: String!
    public var properties: String?
    public var mediaType: MediaType!
    public var mediaOverlay: String?

    public var href: String!
    public var fullHref: String!

    func basePath() -> String! {
        if href == nil || href.isEmpty { return nil }
        var paths = fullHref.components(separatedBy: "/")
        paths.removeLast()
        return paths.joined(separator: "/")
    }
}

// MARK: Equatable

func ==(lhs: FRResource, rhs: FRResource) -> Bool {
    return lhs.id == rhs.id && lhs.href == rhs.href
}
