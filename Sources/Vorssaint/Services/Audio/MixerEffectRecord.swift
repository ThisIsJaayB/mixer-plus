// SPDX-License-Identifier: GPL-3.0-or-later

import AudioToolbox
import Foundation

/// One saved effect in an app's chain: which Audio Unit, how it is shown,
/// whether it is bypassed, and the unit's own saved state.
///
/// Kept as a property list, since a plugin's state is one.
/// A record whose plugin cannot be loaded (uninstalled, or failing to start)
/// is carried through untouched, so saving the chain never throws away the
/// settings of a plugin that is only missing for now.
struct MixerEffectRecord {
    var component: AudioComponentDescription
    var name: String
    var manufacturer: String
    var hasCustomView: Bool
    var isBypassed: Bool
    var state: [String: Any]?

    init(component: AudioComponentDescription, name: String, manufacturer: String,
         hasCustomView: Bool, isBypassed: Bool, state: [String: Any]?) {
        self.component = component
        self.name = name
        self.manufacturer = manufacturer
        self.hasCustomView = hasCustomView
        self.isBypassed = isBypassed
        self.state = state
    }

    /// Nil for anything that does not name an Audio Unit.
    init?(propertyList: Any) {
        guard let plist = propertyList as? [String: Any],
              let type = (plist["type"] as? NSNumber)?.uint32Value,
              let subtype = (plist["subtype"] as? NSNumber)?.uint32Value,
              let maker = (plist["manufacturerCode"] as? NSNumber)?.uint32Value else { return nil }
        component = AudioComponentDescription(componentType: type, componentSubType: subtype,
                                              componentManufacturer: maker,
                                              componentFlags: 0, componentFlagsMask: 0)
        name = plist["name"] as? String ?? "Effect"
        manufacturer = plist["manufacturer"] as? String ?? ""
        hasCustomView = plist["hasCustomView"] as? Bool ?? true
        isBypassed = plist["bypassed"] as? Bool ?? false
        state = plist["state"] as? [String: Any]
    }

    /// A state that cannot be written as a property list is left out: the
    /// plugin then reloads with its defaults instead of spoiling the file.
    var propertyList: [String: Any] {
        var plist: [String: Any] = [
            "type": component.componentType,
            "subtype": component.componentSubType,
            "manufacturerCode": component.componentManufacturer,
            "name": name,
            "manufacturer": manufacturer,
            "hasCustomView": hasCustomView,
            "bypassed": isBypassed,
        ]
        if let state, PropertyListSerialization.propertyList(state, isValidFor: .binary) {
            plist["state"] = state
        }
        return plist
    }

    /// The saved chains of every app, keyed by the app's settings key, from
    /// what the preferences hold. Anything that is not a chain is skipped,
    /// so a damaged or hand-edited entry costs only itself.
    static func chains(fromPropertyList plist: Any?) -> [String: [MixerEffectRecord]] {
        guard let plist = plist as? [String: Any] else { return [:] }
        return plist.compactMapValues { value in
            let records = (value as? [Any])?.compactMap(MixerEffectRecord.init(propertyList:)) ?? []
            return records.isEmpty ? nil : records
        }
    }

    /// What to store for a set of chains, nil when there is nothing to keep.
    static func propertyList(for chains: [String: [MixerEffectRecord]]) -> [String: Any]? {
        let plist = chains.filter { !$0.value.isEmpty }.mapValues { $0.map(\.propertyList) }
        return plist.isEmpty ? nil : plist
    }

    /// The chains in a file written before they moved into the preferences.
    static func chains(fromFileData data: Data?) -> [String: [MixerEffectRecord]] {
        chains(fromPropertyList: data.flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) })
    }

    static func fileData(for chains: [String: [MixerEffectRecord]]) -> Data? {
        try? PropertyListSerialization.data(fromPropertyList: propertyList(for: chains) ?? [:],
                                            format: .binary, options: 0)
    }
}
