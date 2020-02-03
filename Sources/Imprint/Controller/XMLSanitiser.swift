import AEXML
import EPUBCore
import Foundation

class XMLSanitizer {

    class func reparse (data: Data) -> Data {
        do {
            let xmlTarget = AEXMLDocument()

            let attributes = ["xmlns": "http://www.w3.org/1999/xhtml", "xml:lang": "en"]
            let html = xmlTarget.addChild(name: "html", attributes: attributes)
            let head = html.addChild(name: "head")
            head.addChild(name: "meta", attributes: ["http-equiv": "Content-Type", "content": "text/html", "charset": "UTF-8"])

            let body = html.addChild(name: "body")
            let page = body.addChild(name: "div", attributes: ["class": "page"])
            print(xmlTarget.xmlCompact)

            let xmlSource = try AEXMLDocument(xml: data)//, options: /*options*/)

            for child in xmlSource.root.children {
                print(child.name)
            }
            for child in xmlSource.root["head"].children {
                if child.name == "link",
                    let rel = child.attributes["rel"],
                    rel == "stylesheet",
                    let type = child.attributes["type"],
                    type == "text/css" {
                        head.addChild(child)
                }
            }
            page.addChildren(xmlSource.root["body"].children)

            return xmlTarget.xmlSpaces.data(using: .utf8)!
        }
        catch {
            print("\(error)")
        }
        return data
    }
}
