//
//  ListSelectionViewModifier.swift
//  OBAKit
//
//  Created by Alan Chu on 2/11/23.
//

import SwiftUI
import OBAKitCore

private struct ListSelectionViewModifier: ViewModifier {
    var action: () -> Void

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
}

extension View {
    func onListSelection(action: @escaping () -> Void) -> some View {
        modifier(ListSelectionViewModifier(action: action))
    }
}

#if DEBUG

private struct ListSelectionViewModifier_PreviewView: View {
    @State var count = 0

    var body: some View {
        List {
            Section {
                ForEach(0..<5) { num in
                    Text("\(num)")
                        .onListSelection {
                            count += 1
                        }
                }
            } footer: {
                Text("Count: \(count)")
            }
        }
    }
}

struct ListSelectionViewModifier_Previews: PreviewProvider {
    static var previews: some View {
        ListSelectionViewModifier_PreviewView()
    }
}

#endif
