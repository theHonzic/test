//
//  MinimalPackageFeature.swift
//  minimal-package
//
//  Created by Jan Janovec on 19.02.2026.
//

import Foundation
import MinimalPackageCore

/// Internal features for handling payments within the package.
package enum PaymentFeature {
    /// Internal method to process a card payment.
    /// - Parameter country: The country where the payment is being processed.
    internal static func payWithCard(in country: Country) {
    }
}

/// A physical or virtual terminal used to process transactions.
///
/// The `Terminal` class provides the interface for initiating payments across different regions.
///
/// ### Usage Example
/// ```swift
/// let terminal = Terminal()
/// terminal.pay(in: .czechRepublic)
/// ```
public enum Terminal {
    /// Initiates a payment process for the specified country.
    ///
    /// This method routes the payment request through the appropriate feature set for the region.
    /// - Parameter country: The `Country` where the payment should occur.
    ///
    /// > Note: Check the ``Country`` documentation for a list of supported regions.
    public func pay(in country: Country) {
        PaymentFeature.payWithCard(in: country)
    }
}
