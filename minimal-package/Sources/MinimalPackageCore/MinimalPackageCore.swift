//
//  MinimalPackageCore.swift
//  minimal-package
//
//  Created by Jan Janovec on 19.02.2026.
//

import Foundation

/// A collection of supported countries within the MinimalPackage ecosystem.
///
/// Use this enumeration to specify a region for payments or other localized features.
///
/// ### Usage Example
/// ```swift
/// let country = Country.czechRepublic
/// print("Selected country: \(country.rawValue)")
/// ```
///
/// > Warning: Ensure the country is supported by your payment provider before initiating a transaction.
public enum Country: String {
    /// The Czech Republic region.
    case czechRepublic = "Czech Republic"
    
    /// The Slovakia region.
    case slovakia = "Slovakia"
    
    /// The Poland region.
    case poland = "Poland"
    
    /// The Hungary region.
    case hungary = "Hungary"
}

extension Country {
    /// The primary currency associated with the country.
    ///
    /// This property maps each country to its national currency.
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
