//
//  OBAListItemViewModel.swift
//  OBAKit
//
//  Created by Alan Chu on 10/4/20.
//

// MARK: - OBAListViewItem
public protocol OBAListViewItem: Hashable {
    var contentConfiguration: OBAContentConfiguration { get }

    static var customCellType: OBAListViewCell.Type? { get }

    /// Actions to display on the leading side of the cell.
    var leadingActions: [OBAListViewAction<Self>]? { get }

    /// Actions to display on the trailing side of the cell.
    var trailingActions: [OBAListViewAction<Self>]? { get }

    /// Do not implement this yourself, specify actions using `var leadingActions: [OBAListViewAction<_>]`.
    /// The default implementation takes `leadingActions` and sets the `item` property to self.
    var leadingSwipeActions: [OBAListViewAction<Self>]? { get }

    /// Do not implement this yourself, specify actions using `var trailingActions: [OBAListViewAction<_>]`.
    /// The default implementation takes `leadingActions` and sets the `item` property to self.
    var trailingSwipeActions: [OBAListViewAction<Self>]? { get }
}

// MARK: Default implementations
extension OBAListViewItem {
    public static var customCellType: OBAListViewCell.Type? {
        return nil
    }

    public var leadingActions: [OBAListViewAction<Self>]? {
        return nil
    }

    public var trailingActions: [OBAListViewAction<Self>]? {
        return nil
    }

    public var leadingSwipeActions: [OBAListViewAction<Self>]? {
        return leadingActions?.map {
            var action = $0
            action.item = self
            return action
        }
    }

    public var trailingSwipeActions: [OBAListViewAction<Self>]? {
        return trailingActions?.map {
            var action = $0
            action.item = self
            return action
        }
    }
}

// MARK: - Type erase OBAListViewItem
/// To attempt to cast into an `OBAListViewItem`, call `as(:_)`.
///
/// Example:
/// ```swift
/// guard let person = AnyOBAListViewItem.as(Person.self) else { return }
/// ```
public struct AnyOBAListViewItem: OBAListViewItem {
    private let _anyEquatable: AnyEquatable
    private let _contentConfiguration: () -> OBAContentConfiguration
    private let _hash: (_ hasher: inout Hasher) -> Void

    private let _leadingActions: () -> [OBAListViewAction<AnyOBAListViewItem>]?
    private let _trailingActions: () -> [OBAListViewAction<AnyOBAListViewItem>]?
    private let _type: Any

    public init<ViewModel: OBAListViewItem>(_ listCellViewModel: ViewModel) {
        self._anyEquatable = AnyEquatable(listCellViewModel)
        self._contentConfiguration = { return listCellViewModel.contentConfiguration }
        self._hash = listCellViewModel.hash
        self._type = listCellViewModel

        self._leadingActions = { return AnyOBAListViewItem.typeEraseActions(listCellViewModel.leadingSwipeActions) }
        self._trailingActions = { return AnyOBAListViewItem.typeEraseActions(listCellViewModel.trailingSwipeActions) }
    }

    fileprivate static func typeEraseActions<ViewModel: OBAListViewItem>(_ actions: [OBAListViewAction<ViewModel>]?) -> [OBAListViewAction<AnyOBAListViewItem>]? {
        return actions?.map { (typedItem: OBAListViewAction<ViewModel>) -> OBAListViewAction<AnyOBAListViewItem> in
            let typeErased: AnyOBAListViewItem?
            if let item = typedItem.item {
                typeErased = AnyOBAListViewItem(item)
            } else {
                typeErased = nil
            }

            let typeErasedClosure: ((AnyOBAListViewItem) -> Void)?
            if let typedClosure = typedItem.handler {
                typeErasedClosure = { (anyItem: AnyOBAListViewItem) in
                    typedClosure(anyItem.as(ViewModel.self)!)
                }
            } else {
                typeErasedClosure = nil
            }

            return OBAListViewAction(style: typedItem.style,
                                     title: typedItem.title,
                                     image: typedItem.image,
                                     backgroundColor: typedItem.backgroundColor,
                                     item: typeErased,
                                     handler: typeErasedClosure)
        }
    }

    public static var customCellType: OBAListViewCell.Type? {
        fatalError("Illegal. You cannot get the customCellType of AnyOBAListViewItem.")
    }

    public var contentConfiguration: OBAContentConfiguration {
        return _contentConfiguration()
    }

    public var leadingActions: [OBAListViewAction<AnyOBAListViewItem>]? {
        return _leadingActions()
    }

    public var trailingActions: [OBAListViewAction<AnyOBAListViewItem>]? {
        return _trailingActions()
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
private struct AnyEquatable : Equatable {
    let value: Any
    let isEqual: (AnyEquatable) -> Bool
    init<T : Equatable>(_ value: T) {
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
