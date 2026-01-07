import Foundation

struct UPnPDeviceDescription: Equatable {
    struct Service: Equatable {
        let serviceType: String
        let controlURL: URL
    }

    let friendlyName: String
    let services: [Service]
}

final class UPnPDeviceDescriptionParser: NSObject, XMLParserDelegate {
    private let baseURL: URL

    private var buffer: String = ""
    private var friendlyName: String = ""
    private var services: [UPnPDeviceDescription.Service] = []

    private var inService: Bool = false
    private var currentServiceType: String = ""
    private var currentControlURL: String = ""

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func parse(data: Data) -> UPnPDeviceDescription? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { return nil }
        let name = friendlyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return UPnPDeviceDescription(friendlyName: name, services: services)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        buffer = ""
        if elementName.lowercased() == "service" {
            inService = true
            currentServiceType = ""
            currentControlURL = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName.lowercased() {
        case "friendlyname":
            if friendlyName.isEmpty { friendlyName = value }
        case "servicetype" where inService:
            currentServiceType = value
        case "controlurl" where inService:
            currentControlURL = value
        case "service":
            inService = false
            let st = currentServiceType.trimmingCharacters(in: .whitespacesAndNewlines)
            let cu = currentControlURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !st.isEmpty, !cu.isEmpty,
               let url = URL(string: cu, relativeTo: baseURL)?.absoluteURL {
                services.append(.init(serviceType: st, controlURL: url))
            }
            currentServiceType = ""
            currentControlURL = ""
        default:
            break
        }

        buffer = ""
    }
}
