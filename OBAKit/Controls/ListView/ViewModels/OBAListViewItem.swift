//
//  OBAListItemViewModel.swift
//  OBAKit
//
//  Created by Alan Chu on 10/4/20.
//

// MARK: - OBAListViewItem
/// A view model that provides the necessary implementation to compare the identity and equality of
/// two view models for `OBAListView`. Also, defines list row actions, such as what to
/// do when the user taps the row.
public protocol OBAListViewItem: Hashable {
    var contentConfiguration: OBAContentConfiguration { get }

    /// Optional. If your item doesn't use OBAListRowView, you define the custom view type here.
    static var customCellType: OBAListViewCell.Type? { get }

    /// Optional. Action to perform when you select this item.
    var onSelectAction: OBAListViewAction<Self>? { get }

    /// Optional. Action to perform when you delete this item.
    var onDeleteAction: OBAListViewAction<Self>? { get }

    /// Optional. Contextual actions to display on the leading side of the cell.
    /// There is no need to set `item` for your actions, `OBAListView` will automatically set `item`.
    var leadingContextualActions: [OBAListViewContextualAction<Self>]? { get }

    /// Optional. Contextual actions to display on the trailing side of the cell.
    /// There is no need to set `item` for your actions, `OBAListView` will automatically set `item`.
    var trailingContextualActions: [OBAListViewContextualAction<Self>]? { get }

    var typeErased: AnyOBAListViewItem { get }
}

// MARK: Default implementations
extension OBAListViewItem {
    public static var customCellType: OBAListViewCell.Type? {
        return nil
    }

    public var onDeleteAction: OBAListViewAction<Self>? {
        return nil
    }

    public var leadingContextualActions: [OBAListViewContextualAction<Self>]? {
        return nil
    }

    public var trailingContextualActions: [OBAListViewContextualAction<Self>]? {
        return nil
    }

    public var typeErased: AnyOBAListViewItem {
        return AnyOBAListViewItem(self)
    }
}

// MARK: - Type erase OBAListViewItem
/// A type-erased OBAListViewItem.
///
/// To attempt to cast into an `OBAListViewItem`, call `as(:_)`. For example:
/// ```swift
/// let person: Person? = AnyOBAListViewItem.as(Person.self)
/// ```
public struct AnyOBAListViewItem: OBAListViewItem {
    private let _anyEquatable: AnyEquatable
    private let _contentConfiguration: () -> OBAContentConfiguration
    private let _hash: (_ hasher: inout Hasher) -> Void

    private let _onSelectAction: () -> OBAListViewAction<AnyOBAListViewItem>?
    private let _onDeleteAction: () -> OBAListViewAction<AnyOBAListViewItem>?
    private let _leadingContextualActions: () -> [OBAListViewContextualAction<AnyOBAListViewItem>]?
    private let _trailingContextualActions: () -> [OBAListViewContextualAction<AnyOBAListViewItem>]?
    private let _type: Any

    public init<ViewModel: OBAListViewItem>(_ listCellViewModel: ViewModel) {
        self._anyEquatable = AnyEquatable(listCellViewModel)
        self._contentConfiguration = { return listCellViewModel.contentConfiguration }
        self._hash = listCellViewModel.hash
        self._type = listCellViewModel

        self._onSelectAction = { return AnyOBAListViewItem.typeEraseAction(listCellViewModel.onSelectAction) }
        self._onDeleteAction = { return AnyOBAListViewItem.typeEraseAction(listCellViewModel.onDeleteAction) }
        self._leadingContextualActions = { return AnyOBAListViewItem.typeEraseActions(listCellViewModel.leadingContextualActions) }
        self._trailingContextualActions = { return AnyOBAListViewItem.typeEraseActions(listCellViewModel.trailingContextualActions) }
    }

    fileprivate static func typeEraseAction<ViewModel: OBAListViewItem>(
        _ action: OBAListViewAction<ViewModel>?
    ) -> OBAListViewAction<AnyOBAListViewItem>? {
        let typeErasedClosure: OBAListViewAction<AnyOBAListViewItem>?
        if let typedClosure = action {
            typeErasedClosure = { (anyItem: AnyOBAListViewItem) in
                typedClosure(anyItem.as(ViewModel.self)!)
            }
        } else {
            typeErasedClosure = nil
        }

        return typeErasedClosure
    }

    fileprivate static func typeEraseActions<ViewModel: OBAListViewItem>(
        _ actions: [OBAListViewContextualAction<ViewModel>]?
    ) -> [OBAListViewContextualAction<AnyOBAListViewItem>]? {
        return actions?.map { (typedItem: OBAListViewContextualAction<ViewModel>) -> OBAListViewContextualAction<AnyOBAListViewItem> in
            let typeErased: AnyOBAListViewItem?
            if let item = typedItem.item {
                typeErased = AnyOBAListViewItem(item)
            } else {
                typeErased = nil
            }

            let typeErasedAction = typeEraseAction(typedItem.handler)

            return OBAListViewContextualAction(
                style: typedItem.style,
                title: typedItem.title,
                image: typedItem.image,
                backgroundColor: typedItem.backgroundColor,
                item: typeErased,
                handler: typeErasedAction)
        }
    }

    public static var customCellType: OBAListViewCell.Type? {
        fatalError("Illegal. You cannot get the customCellType of AnyOBAListViewItem.")
    }

    public var contentConfiguration: OBAContentConfiguration {
        return _contentConfiguration()
    }

    public var onSelectAction: OBAListViewAction<AnyOBAListViewItem>? {
        return _onSelectAction()
    }

    public var onDeleteAction: OBAListViewAction<AnyOBAListViewItem>? {
        return _onDeleteAction()
    }

    public var leadingContextualActions: [OBAListViewContextualAction<AnyOBAListViewItem>]? {
        return _leadingContextualActions()
    }

    public var trailingContextualActions: [OBAListViewContextualAction<AnyOBAListViewItem>]? {
        return _trailingContextualActions()
    }

    public func hash(into hasher: inout Hasher) {
        self._hash(&hasher)
    }

    public static func == (lhs: AnyOBAListViewItem, rhs: AnyOBAListViewItem) -> Bool {
        return lhs._anyEquatable == rhs._anyEquatable
    }

    func `as`<OBAViewModel: OBAListViewItem>(_ expectedType: OBAViewModel.Type) -> OBAViewModel? {
        return self._type as? OBAViewModel
    }
}

// MARK: - AnyEquatable for type erased types
// Source: https://gist.github.com/pyrtsa/f5dbf7fff53e834936470762960357a4

// Quick hack to avoid changing the AnyEquatable implementation below.
private extension Equatable { typealias EqualSelf = Self }

/// Existential wrapper around Equatable.
private struct AnyEquatable: Equatable {
    let value: Any
    let isEqual: (AnyEquatable) -> Bool
    init<T: Equatable>(_ value: T) {
        self.value = value
        self.isEqual = {r in
            guard let other = r.value as? T.EqualSelf else { return false }
            return value == other
        }
    }

    static func == (lhs: AnyEquatable, rhs: AnyEquatable) -> Bool {
        lhs.isEqual(rhs)
    }
}
