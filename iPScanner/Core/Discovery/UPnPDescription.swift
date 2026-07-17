import Foundation

/// The interesting fields of a UPnP device description document.
///
/// SSDP's SERVER header names the stack ("Linux/3.4 UPnP/1.0"); this names the *device*
/// ("Living Room", "Sonos", "PLAY:1"). Worth the extra GET for that reason.
struct UPnPDescription: Hashable, Sendable {
    var friendlyName: String?
    var manufacturer: String?
    var modelName: String?
    var modelNumber: String?
    var deviceType: String?

    var isEmpty: Bool {
        friendlyName == nil && manufacturer == nil && modelName == nil
            && modelNumber == nil && deviceType == nil
    }

    /// Everything this document says, as one lowercase string for phrase matching.
    var descriptionText: String {
        [friendlyName, manufacturer, modelName, modelNumber, deviceType]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
    }
}

extension UPnPDescription {
    /// Parses a `device` description. Returns nil for anything that is not one.
    ///
    /// Takes the *first* occurrence of each field: a description can embed a list of child
    /// devices, each with its own friendlyName, and the root device is the one being asked about.
    static func parse(_ data: Data) -> UPnPDescription? {
        let delegate = Parser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        return delegate.result.isEmpty ? nil : delegate.result
    }

    private final class Parser: NSObject, XMLParserDelegate {
        var result = UPnPDescription()
        private var currentElement = ""
        private var currentText = ""

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String]
        ) {
            currentElement = elementName.lowercased()
            currentText = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            currentText += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?
        ) {
            let value = currentText.trimmed
            defer { currentText = "" }
            guard !value.isEmpty else { return }

            switch elementName.lowercased() {
            case "friendlyname" where result.friendlyName == nil:
                result.friendlyName = value
            case "manufacturer" where result.manufacturer == nil:
                result.manufacturer = value
            case "modelname" where result.modelName == nil:
                result.modelName = value
            case "modelnumber" where result.modelNumber == nil:
                result.modelNumber = value
            case "devicetype" where result.deviceType == nil:
                result.deviceType = value
            default:
                break
            }
        }
    }
}
