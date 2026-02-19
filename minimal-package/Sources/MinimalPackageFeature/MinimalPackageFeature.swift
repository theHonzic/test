//
//  MinimalPackageFeature.swift
//  minimal-package
//
//  Created by Jan Janovec on 19.02.2026.
//

import Foundation
import MinimalPackageCore

package enum PaymentFeature {
    internal static func payWithCard(in country: Country) {
    }
}

public enum Terminal {
    public func pay(in country: Country) {
        PaymentFeature.payWithCard(in: country)
    }
}
