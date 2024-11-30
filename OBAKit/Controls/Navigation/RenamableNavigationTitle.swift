//
//  RenamableNavigationTitle.swift
//  OBAKit
//
//  Created by Alan Chu on 1/26/23.
//

import SwiftUI

fileprivate struct RenamableNavigationTitle<MenuItems: View>: ViewModifier {
    @Binding var title: String
    let menuItems: MenuItems

    init(title: Binding<String>, @ViewBuilder menuItems: () -> MenuItems) {
        self._title = title
        self.menuItems = menuItems()
    }

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if isEditing {
                        textFieldNavigationTitle
                    } else {
                        standardNavigationTitle
                    }
                }
            }
            .onAppear {
                // Set initial value of `textFieldValue`. There is currently no
                // way to have an `onChange` to fire on initial value.
                textFieldValue = title
            }
            .onChange(of: title) { _, newValue in
                textFieldValue = newValue
            }
            .onChange(of: isEditing) { _, newIsEditing in
                isFocusedOnTextField = newIsEditing
            }
    }

    @State private var isEditing: Bool = false
    @FocusState private var isFocusedOnTextField: Bool
    @State private var textFieldValue: String = ""

    private var textFieldNavigationTitle: some View {
        TextField("", text: $textFieldValue)
            .textFieldStyle(.roundedBorder)
            .buttonBorderShape(.capsule)
            .focused($isFocusedOnTextField)
            .font(.headline)
            .multilineTextAlignment(.center)
            .submitLabel(.done)
            .onSubmit {
                if textFieldValue.isEmpty {
                    textFieldValue = self.title
                } else {
                    self.title = textFieldValue
                }

                isEditing = false
            }

            // If this was enclosed in a Form, `submitScope` prevents the "submit"
            // action (return key) from propagating to the Form itself.
            .submitScope()
    }

    private var standardNavigationTitle: some View {
        // Using GeometryReader to manually place the Label in the center with a specific width,
        // because of "Menu's Label in principal toolbar does not respect toolbar's width" (FB11969195)
        GeometryReader { geometry in
            Menu {
                Button {
                    isEditing = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }

                menuItems
            } label: {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .truncationMode(.tail)

                    Label("Menu", systemImage: "chevron.down.circle")
                        .symbolVariant(.fill)
                        .symbolRenderingMode(.hierarchical)
                        .labelStyle(.iconOnly)
                        .font(.subheadline)
                }
                .frame(maxWidth: geometry.size.width, alignment: .center)
                .foregroundColor(Color.primary)
            }
            .frame(maxWidth: geometry.size.width, alignment: .center)
            .position(x: geometry.frame(in: .local).midX, y: geometry.frame(in: .local).midY)
        }
    }
}

extension View {
    /// Creates a navigation title that may be renamed and any additional actions. The View must be enclosed in a `NavigationView`.
    /// This is a polyfill for iOS 15, and is equivalent to setting `navigationTitle` to a `Binding<String>` and setting `toolbarTitleMenu`.
    ///
    /// - precondition: `title` cannot be an empty string.
    /// - postcondition: The title will not be set to an empty string. If the user inputs an empty title, it is defaulted back to the pre-editing title.
    /// - parameter title: The string to display in the navigation title. When the user renames the text, it is updating the binding.
    /// - parameter menuItems: Additional actions to display in the menu. A `Rename` action is already included by default.
    @ViewBuilder
    func renamableNavigationTitle<C>(
        _ title: Binding<String>,
        @ViewBuilder menuItems: () -> C = { EmptyView() }
    ) -> some View where C: View {
        self
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(title)
            .toolbarTitleMenu {
                RenameButton()
                menuItems()
            }
    }
}

// MARK: - Previews

fileprivate struct RenamableNavigationTitlePreview: View {
    @State var title = "Hello, world!LONGLONGLONGLONGLONGLONGLONGLONG"

    @State var isShowingAlert = false

    var body: some View {
        VStack {
            (Text("Current title: ") + Text(title))

            Divider()

            Text("Test updating the binding from NOT the TextField:")
            Button("Append PLUS to title") {
                title += "+"
            }
        }
        .renamableNavigationTitle($title)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Leading", action: {})
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Trailing", action: {})
            }
        }
    }
}

struct RenamableNavigationTitle_Previews: PreviewProvider {
    static var previews: some View {
        // Test the truncation of the navigation title, and title respecting
        // other toolbar items.
        NavigationView {
            RenamableNavigationTitlePreview(title: "asdfLongLongLongLongLongLongLongLongLong")
        }
        .previewDisplayName("long title")

        NavigationView {
            RenamableNavigationTitlePreview()
        }
        .previewDisplayName("No title")
    }
}
