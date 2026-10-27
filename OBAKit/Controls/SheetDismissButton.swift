//
//  SheetDismissButton.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The Close, Cancel, or Done button in a sheet's toolbar.
///
/// On iOS 26 and later it takes the system's role-based glyph (an X or a
/// checkmark). Besides matching the rest of the system, the glyph is what lets the
/// button move into the vertical bar on iPhone Duo: the system leaves a text-only
/// item out of a vertical bar, which strands the sheet's content beside an empty
/// column reserved for it. Earlier releases keep the text button.
struct SheetDismissButton: View {
    enum Kind {
        case close
        case cancel
        case done
    }

    let kind: Kind
    let action: () -> Void

    init(_ kind: Kind, action: @escaping () -> Void) {
        self.kind = kind
        self.action = action
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(role: role, action: action)
        } else {
            Button(title, action: action)
        }
    }

    @available(iOS 26.0, *)
    var role: ButtonRole {
        switch kind {
        case .close: .close
        case .cancel: .cancel
        case .done: .confirm
        }
    }

    var title: String {
        switch kind {
        case .close: Strings.close
        case .cancel: Strings.cancel
        case .done: Strings.done
        }
    }
}
