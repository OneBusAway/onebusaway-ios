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

}

// MARK: Default implementations
extension OBAListViewItem {
    public static var customCellType: OBAListViewCell.Type? {
        return nil
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
    private let _type: Any

    public init<OBAViewModel: OBAListViewItem>(_ listCellViewModel: OBAViewModel) {
        self._anyEquatable = AnyEquatable(listCellViewModel)
        self._contentConfiguration = { return listCellViewModel.contentConfiguration }
        self._hash = listCellViewModel.hash
        self._type = listCellViewModel
    }

    public static var customCellType: OBAListViewCell.Type? {
        fatalError("Illegal. You cannot get the customCellType of AnyOBAListViewItem.")
    }

    public var contentConfiguration: OBAContentConfiguration {
        return _contentConfiguration()
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
