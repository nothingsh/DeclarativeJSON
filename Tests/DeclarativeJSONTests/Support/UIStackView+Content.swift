import UIKit
@testable import DeclarativeJSON

extension UIStackView {

    /// The arranged views built from the stack's children, without the
    /// filler that ends a `vstack` or an `hstack`.
    var contentViews: [UIView] {
        arrangedSubviews.filter { !($0 is StackFiller) }
    }
}
