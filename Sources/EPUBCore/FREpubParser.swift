//
//  FREpubParser.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 04/05/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import Foundation
import AEXML
import Harness
import LoggerAPI
import ZipReader

public class FREpubParser {

    public let book = FRBook()

    private let _url: URL

    private var _resourcesBasePath: String = ""

    private let _zipReader: ZipReader

    public init? (bookURL url: URL) {
        _url = url
        let reader: ZipReader
        do {
            reader = try ZipReader(url: url)
        } catch let error {
            Log.error("Could not open \(url): \(error.localizedDescription)")
            return nil
        }
        _zipReader = reader
    }

    /// Parse the Cover Image from an epub file.
    ///
    /// - Parameters:
    ///   - epubPath: Epub path on the disk.
    ///   - unzipPath: Path to unzip the compressed epub.
    /// - Returns: The book cover as a Data object
    /// - Throws: `FolioReaderError`
    public func parseCoverImage() throws -> Data {
        guard let book = try? readEpub(),
            let coverImage = book.coverImage else {
                throw FolioReaderError.coverNotAvailable
        }
        let image: Data
        do {
            image = try Data(contentsOf: URL(fileURLWithPath: coverImage.fullHref))
        } catch {
            throw FolioReaderError.invalidImage(path: coverImage.fullHref)
        }

        return image
    }

    public func readResource (path: String) throws -> ZippedFile {
        return try _zipReader.file(path: path)

    }

    /// Parse the book title from an epub file.
    ///
    /// - Parameters:
    ///   - epubPath: Epub path on the disk.
    ///   - unzipPath: Path to unzip the compressed epub.
    /// - Returns: The book title
    /// - Throws: `FolioReaderError`
    public func parseTitle() throws -> String {
        guard let book = try? readEpub(), let title = book.title else {
             throw FolioReaderError.titleNotAvailable
        }
        return title
    }


    /// Parse the book Author name from an epub file.
    ///
    /// - Parameters:
    ///   - epubPath: Epub path on the disk.
    ///   - unzipPath: Path to unzip the compressed epub.
    /// - Returns: The author name
    /// - Throws: `FolioReaderError`
    public func parseAuthorName() throws -> String {
        guard let book = try? readEpub(), let authorName = book.authorName else {
            throw FolioReaderError.authorNameNotAvailable
        }
        return authorName
    }

    /// Unzip, delete and read an epub file.
    ///
    /// - Parameters:
    ///   - withEpubPath: Epub path on the disk
    ///   - removeEpub: Should remove the original file?
    ///   - unzipPath: Path to unzip the compressed epub.
    /// - Returns: `FRBook` Object
    /// - Throws: `FolioReaderError`
    public func readEpub() throws -> FRBook {

        let bookName = _url.lastPathComponent

        book.name = bookName
        try readContainer()
        try readOpf()
        return self.book
    }

    /// Read and parse container.xml file.
    ///
    /// - Parameter bookBasePath: The base book path
    /// - Throws: `FolioReaderError`
    private func readContainer() throws {
        let containerFile = try _zipReader.file(path: "META-INF/container.xml")
        let xmlDoc = try AEXMLDocument(xml: containerFile.data)
        let opfResource = FRResource()
        opfResource.href = xmlDoc.root["rootfiles"]["rootfile"].attributes["full-path"]
        guard let fullPath = xmlDoc.root["rootfiles"]["rootfile"].attributes["full-path"] else {
            throw FolioReaderError.fullPathEmpty
        }
        opfResource.mediaType = MediaType.by(fileName: fullPath)
        book.opfResource = opfResource
        _resourcesBasePath = book.opfResource.href.deletingLastPathComponent
    }

    /// Read and parse .opf file.
    ///
    /// - Parameter bookBasePath: The base book path
    /// - Throws: `FolioReaderError`
    private func readOpf() throws {
        guard let opfPath = book.opfResource.href else {
            throw FolioReaderError.errorInOpf
        }
        var identifier: String?

        let opfFile = try _zipReader.file(path: opfPath)
        let xmlDoc = try AEXMLDocument(xml: opfFile.data)

        // Base OPF info
        if let package = xmlDoc.children.first {
            identifier = package.attributes["unique-identifier"]

            if let version = package.attributes["version"] {
                book.version = Double(version)
            }
        }

        // Parse and save each "manifest item"
        xmlDoc.root["manifest"]["item"].all?.forEach {
            let resource = FRResource()
            resource.id = $0.attributes["id"]
            resource.properties = $0.attributes["properties"]
            resource.href = $0.attributes["href"]
            resource.fullHref = _resourcesBasePath.appendingPathComponent(resource.href).removingPercentEncoding
            resource.mediaType = MediaType.by(name: $0.attributes["media-type"] ?? "", fileName: resource.href)
            resource.mediaOverlay = $0.attributes["media-overlay"]

            // if a .smil file is listed in resources, go parse that file now and save it on book model
            if (resource.mediaType != nil && resource.mediaType == .smil) {
                readSmilFile(resource)
            }

            book.resources.add(resource)
        }

        book.smils.basePath = _resourcesBasePath

        // Read metadata
        book.metadata = readMetadata(xmlDoc.root["metadata"].children)

        // Read the book unique identifier
        if let identifier = identifier, let uniqueIdentifier = book.metadata.find(identifierById: identifier) {
            book.uniqueIdentifier = uniqueIdentifier.value
        }

        // Read the cover image
        let coverImageId = book.metadata.find(byName: "cover")?.content
        if let coverImageId = coverImageId, let coverResource = book.resources.findById(coverImageId) {
            book.coverImage = coverResource
        } else if let coverResource = book.resources.findByProperty("cover-image") {
            book.coverImage = coverResource
        }

        // Specific TOC for ePub 2 and 3
        // Get the first resource with the NCX mediatype
        if let tocResource = book.resources.findByMediaType(MediaType.ncx) {
            book.tocResource = tocResource
        } else if let tocResource = book.resources.findByExtension(MediaType.ncx.defaultExtension) {
            // Non-standard books may use wrong mediatype, fallback with extension
            book.tocResource = tocResource
        } else if let tocResource = book.resources.findByProperty("nav") {
            book.tocResource = tocResource
        }

        precondition(book.tocResource != nil, "ERROR: Could not find table of contents resource. The book don't have a TOC resource.")

        // The book TOC
        book.tableOfContents = findTableOfContents()
        book.flatTableOfContents = flatTOC

        // Read Spine
        let spine = xmlDoc.root["spine"]
        book.spine = readSpine(spine.children)

        // Page progress direction `ltr` or `rtl`
        if let pageProgressionDirection = spine.attributes["page-progression-direction"] {
            book.spine.pageProgressionDirection = pageProgressionDirection
        }
    }

    /// Reads and parses a .smil file.
    ///
    /// - Parameter resource: A `FRResource` to read the smill
    private func readSmilFile(_ resource: FRResource) {
        var smilZipFile: ZippedFile
        do {
            smilZipFile = try _zipReader.file(path: resource.fullHref)
        } catch {
            print("Cannot read .smil file: " + resource.href)
            return
        }
        do {
            let smilData = smilZipFile.data
            var smilFile = FRSmilFile(resource: resource)
            let xmlDoc = try AEXMLDocument(xml: smilData)

            let children = xmlDoc.root["body"].children

            if children.count > 0 {
                smilFile.data.append(contentsOf: readSmilFileElements(children))
            }

            book.smils.add(smilFile)
        } catch {
            print("Cannot read .smil file: "+resource.href)
        }
    }

    private func readSmilFileElements(_ children: [AEXMLElement]) -> [FRSmilElement] {
        var data = [FRSmilElement]()

        // convert each smil element to a FRSmil object
        children.forEach{
            let smil = FRSmilElement(name: $0.name, attributes: $0.attributes)

            // if this element has children, convert them to objects too
            if $0.children.count > 0 {
                smil.children.append(contentsOf: readSmilFileElements($0.children))
            }

            data.append(smil)
        }

        return data
    }

    /// Read and parse the Table of Contents.
    ///
    /// - Returns: A list of toc references
    private func findTableOfContents() -> [FRTocReference] {
        var tableOfContent = [FRTocReference]()
        var tocItems: [AEXMLElement]?
        guard let tocResource = book.tocResource else { return tableOfContent }
        let tocPath = _resourcesBasePath.appendingPathComponent(tocResource.href)
        let tocFile: ZippedFile
        do {
            tocFile = try _zipReader.file(path: tocPath)
            let xmlDoc = try AEXMLDocument(xml: tocFile.data)
            if tocResource.mediaType == MediaType.ncx {
                if let itemsList = xmlDoc.root["navMap"]["navPoint"].all {
                    tocItems = itemsList
                }
            } else {
                if let nav = xmlDoc.root["body"]["nav"].first, let itemsList = nav["ol"]["li"].all {
                    tocItems = itemsList
                } else if let nav = findNavTag(xmlDoc.root["body"]), let itemsList = nav["ol"]["li"].all {
                    tocItems = itemsList
                }
            }
        } catch {
            print("Cannot find Table of Contents.")
        }

        guard let items = tocItems else { return tableOfContent }

        for item in items {
            guard let ref = readTOCReference(item) else { continue }
            tableOfContent.append(ref)
        }

        return tableOfContent
    }

    /// Recursively finds a `<nav>` tag on html.
    ///
    /// - Parameter element: An `AEXMLElement`, usually the `<body>`
    /// - Returns: If found the `<nav>` `AEXMLElement`
    @discardableResult func findNavTag(_ element: AEXMLElement) -> AEXMLElement? {
        for element in element.children {
            if let nav = element["nav"].first {
                return nav
            } else {
                findNavTag(element)
            }
        }
        return nil
    }

    fileprivate func readTOCReference(_ navpointElement: AEXMLElement) -> FRTocReference? {
        var label = ""

        if book.tocResource?.mediaType == MediaType.ncx {
            if let labelText = navpointElement["navLabel"]["text"].value {
                label = labelText
            }

            guard let reference = navpointElement["content"].attributes["src"] else { return nil }
            let hrefSplit = reference.split {$0 == "#"}.map { String($0) }
            let fragmentID = hrefSplit.count > 1 ? hrefSplit[1] : ""
            let href = hrefSplit[0]

            let resource = book.resources.findByHref(href)
            let toc = FRTocReference(title: label, resource: resource, fragmentID: fragmentID)

            // Recursively find child
            if let navPoints = navpointElement["navPoint"].all {
                for navPoint in navPoints {
                    guard let item = readTOCReference(navPoint) else { continue }
                    toc.children.append(item)
                }
            }
            return toc
        } else {
            if let labelText = navpointElement["a"].value {
                label = labelText
            }

            guard let reference = navpointElement["a"].attributes["href"] else { return nil }
            let hrefSplit = reference.split {$0 == "#"}.map { String($0) }
            let fragmentID = hrefSplit.count > 1 ? hrefSplit[1] : ""
            let href = hrefSplit[0]

            let resource = book.resources.findByHref(href)
            let toc = FRTocReference(title: label, resource: resource, fragmentID: fragmentID)

            // Recursively find child
            if let navPoints = navpointElement["ol"]["li"].all {
                for navPoint in navPoints {
                    guard let item = readTOCReference(navPoint) else { continue }
                    toc.children.append(item)
                }
            }
            return toc
        }
    }

    // MARK: - Recursive add items to a list

    var flatTOC: [FRTocReference] {
        var tocItems = [FRTocReference]()

        for item in book.tableOfContents {
            tocItems.append(item)
            tocItems.append(contentsOf: countTocChild(item))
        }
        return tocItems
    }

    func countTocChild(_ item: FRTocReference) -> [FRTocReference] {
        var tocItems = [FRTocReference]()

        item.children.forEach {
            tocItems.append($0)
        }
        return tocItems
    }

    /// Read and parse <metadata>.
    ///
    /// - Parameter tags: XHTML tags
    /// - Returns: Metadata object
    fileprivate func readMetadata(_ tags: [AEXMLElement]) -> FRMetadata {
        let metadata = FRMetadata()

        for tag in tags {
            if tag.name == "dc:title" {
                metadata.titles.append(tag.value ?? "")
            }

            if tag.name == "dc:identifier" {
                let identifier = Identifier(id: tag.attributes["id"], scheme: tag.attributes["opf:scheme"], value: tag.value)
                metadata.identifiers.append(identifier)
            }

            if tag.name == "dc:language" {
                let language = tag.value ?? metadata.language
                metadata.language = language != "en" ? language : metadata.language
            }

            if tag.name == "dc:creator" {
                metadata.creators.append(Author(name: tag.value ?? "", role: tag.attributes["opf:role"] ?? "", fileAs: tag.attributes["opf:file-as"] ?? ""))
            }

            if tag.name == "dc:contributor" {
                metadata.creators.append(Author(name: tag.value ?? "", role: tag.attributes["opf:role"] ?? "", fileAs: tag.attributes["opf:file-as"] ?? ""))
            }

            if tag.name == "dc:publisher" {
                metadata.publishers.append(tag.value ?? "")
            }

            if tag.name == "dc:description" {
                metadata.descriptions.append(tag.value ?? "")
            }

            if tag.name == "dc:subject" {
                metadata.subjects.append(tag.value ?? "")
            }

            if tag.name == "dc:rights" {
                metadata.rights.append(tag.value ?? "")
            }

            if tag.name == "dc:date" {
                metadata.dates.append(EventDate(date: tag.value ?? "", event: tag.attributes["opf:event"] ?? ""))
            }

            if tag.name == "meta" {
                if tag.attributes["name"] != nil {
                    metadata.metaAttributes.append(Meta(name: tag.attributes["name"], content: tag.attributes["content"]))
                }

                if tag.attributes["property"] != nil && tag.attributes["id"] != nil {
                    metadata.metaAttributes.append(Meta(id: tag.attributes["id"], property: tag.attributes["property"], value: tag.value))
                }

                if tag.attributes["property"] != nil {
                    metadata.metaAttributes.append(Meta(property: tag.attributes["property"], value: tag.value, refines: tag.attributes["refines"]))
                }
            }
        }
        return metadata
    }

    /// Read and parse <spine>.
    ///
    /// - Parameter tags: XHTML tags
    /// - Returns: Spine object
    fileprivate func readSpine(_ tags: [AEXMLElement]) -> FRSpine {
        let spine = FRSpine()

        for tag in tags {
            guard let idref = tag.attributes["idref"] else { continue }
            var linear = true

            if tag.attributes["linear"] != nil {
                linear = tag.attributes["linear"] == "yes" ? true : false
            }

            if book.resources.containsById(idref) {
                guard let resource = book.resources.findById(idref) else { continue }
                spine.spineReferences.append(Spine(resource: resource, linear: linear))
            }
        }
        return spine
    }

    /// Skip a file from iCloud backup.
    ///
    /// - Parameter url: File URL
    /// - Throws: Error if not possible
    fileprivate func addSkipBackupAttributeToItemAtURL(_ url: URL) throws {
        assert(FileManager.default.fileExists(atPath: url.path))

        var urlToExclude = url
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try urlToExclude.setResourceValues(resourceValues)
    }

}
