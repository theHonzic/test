//
//  MinimalPackageCore.swift
//  minimal-package
//
//  Created by Jan Janovec on 19.02.2026.
//

import Foundation

public enum Country: String {
    case czechRepublic = "Czech Republic"
    case slovakia = "Slovakia"
    case poland = "Poland"
    case hungary = "Hungary"
}

internal extension Country {
    var currency: Currency {
        switch self {
        case .czechRepublic:
            return .czechKoruna
        case .slovakia:
            return .euro
        case .poland:
            return .polishZloty
        case .hungary:
            return .hungarianForint
        }
    }
}

internal enum Currency {
    case czechKoruna
    case euro
    case polishZloty
    case hungarianForint
}
