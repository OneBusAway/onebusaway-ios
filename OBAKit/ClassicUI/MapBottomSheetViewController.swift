//
//  MapBottomSheetViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore
import MapKit
import SwiftUI

// MARK: - Delegate

protocol MapBottomSheetDelegate: AnyObject {
    func mapBottomSheetDidTapRecent(_ sheet: MapBottomSheetViewController)
    func mapBottomSheetDidTapBookmarks(_ sheet: MapBottomSheetViewController)
    func mapBottomSheetDidTapMore(_ sheet: MapBottomSheetViewController)
    func mapBottomSheet(_ sheet: MapBottomSheetViewController, didSubmitSearch request: SearchRequest)
    func mapBottomSheet(_ sheet: MapBottomSheetViewController, didSelectMapItem mapItem: MKMapItem)
    func mapBottomSheet(_ sheet: MapBottomSheetViewController, didSelectStop stop: Stop)
    func mapBottomSheetDidCancelSearch(_ sheet: MapBottomSheetViewController)
}

// MARK: - MapBottomSheetViewController

/// Apple Maps-style persistent bottom sheet.
///
/// Default state — pill (🔍 placeholder 🎤) + ☰ circle
/// Search state  — same pill but with live UITextField + ☰ becomes cancel
///                 + results table below (recent searches, quick search, placemarks)
final class MapBottomSheetViewController: UIViewController {

    // MARK: - Public

    weak var delegate: MapBottomSheetDelegate?
    var onSearchBecameActive: (() -> Void)?
    var onDetailShown: (() -> Void)?

    func setGrabHandleVisible(_ visible: Bool) {
        grabHandle.isHidden = !visible
    }

    // MARK: - Private

    private let application: Application
    private(set) var isInSearchMode = false

    // MARK: - Shared pill container (used in both states)

    private lazy var pillBlur: UIVisualEffectView = {
        let effect: UIVisualEffect
        if #available(iOS 26.0, *) {
            effect = UIGlassEffect()
        } else {
            effect = UIBlurEffect(style: .systemUltraThinMaterial)
        }
        let blur = UIVisualEffectView(effect: effect)
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.layer.cornerRadius = 20
        blur.layer.cornerCurve = .continuous
        blur.clipsToBounds = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(pillTapped))
        tap.cancelsTouchesInView = false
        blur.addGestureRecognizer(tap)
        blur.isUserInteractionEnabled = true
        return blur
    }()

    // Search icon — always visible inside the pill
    private lazy var searchIcon: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.tintColor = .secondaryLabel
        iv.contentMode = .scaleAspectFit
        iv.setContentHuggingPriority(.required, for: .horizontal)
        return iv
    }()

    // Placeholder label — visible in default state
    private lazy var placeholderLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.textColor = .secondaryLabel
        l.font = UIFont.preferredFont(forTextStyle: .body)
        l.adjustsFontForContentSizeCategory = true
        return l
    }()

    // Live text field — visible in search state, same font/color as placeholder
    private lazy var searchTextField: UITextField = {
        let tf = UITextField()
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.font = UIFont.preferredFont(forTextStyle: .body)
        tf.textColor = .label
        tf.returnKeyType = .search
        tf.clearButtonMode = .always
        tf.delegate = self
        tf.isHidden = true
        tf.addTarget(self, action: #selector(searchTextChanged), for: .editingChanged)
        return tf
    }()

    // Mic button — kept as property but not shown
    private lazy var micButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    // MARK: - Right-side button (☰ default / cancel in search)

    private lazy var rightButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setImage(UIImage(systemName: "line.3.horizontal"), for: .normal)
        btn.tintColor = .label
        btn.menu = makeNavigationMenu()
        btn.showsMenuAsPrimaryAction = true
        btn.accessibilityLabel = OBALoc(
            "map_controller.menu_button.accessibility_label",
            value: "Navigation menu",
            comment: "Accessibility label for the navigation menu button."
        )
        return btn
    }()

    private lazy var rightButtonContainer: UIVisualEffectView = {
        let effect: UIVisualEffect
        if #available(iOS 26.0, *) {
            effect = UIGlassEffect()
        } else {
            effect = UIBlurEffect(style: .systemUltraThinMaterial)
        }
        let blur = UIVisualEffectView(effect: effect)
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.layer.cornerRadius = 20
        blur.layer.cornerCurve = .circular
        blur.clipsToBounds = true
        blur.contentView.addSubview(rightButton)
        NSLayoutConstraint.activate([
            rightButton.topAnchor.constraint(equalTo: blur.contentView.topAnchor),
            rightButton.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor),
            rightButton.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor),
            rightButton.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor)
        ])
        return blur
    }()

    private lazy var grabHandle: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor.tertiaryLabel
        v.layer.cornerRadius = 2.5
        v.clipsToBounds = true
        v.isAccessibilityElement = false
        return v
    }()

    // MARK: - Results table (search mode only)

    private lazy var resultsTable: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.dataSource = self
        tv.delegate = self
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tv.backgroundColor = .clear
        tv.isHidden = true
        tv.keyboardDismissMode = .onDrag
        return tv
    }()

    // Detail view container — shown when a map item is selected
    private lazy var detailContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        return v
    }()

    private var embeddedDetailVC: UIViewController?

    // MARK: - Search data

    private lazy var searchInteractor = SearchInteractor(application: application, delegate: self)
    private var searchSections: [SearchListSection] = []

    // MARK: - Init

    init(application: Application) {
        self.application = application
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        // Build pill content: [🔍] [placeholder / textfield]
        let pillRow = UIStackView(arrangedSubviews: [searchIcon, placeholderLabel, searchTextField])
        pillRow.translatesAutoresizingMaskIntoConstraints = false
        pillRow.axis = .horizontal
        pillRow.spacing = 10
        pillRow.alignment = .center
        pillBlur.contentView.addSubview(pillRow)

        NSLayoutConstraint.activate([
            pillRow.topAnchor.constraint(equalTo: pillBlur.contentView.topAnchor),
            pillRow.bottomAnchor.constraint(equalTo: pillBlur.contentView.bottomAnchor),
            pillRow.leadingAnchor.constraint(equalTo: pillBlur.contentView.leadingAnchor, constant: 14),
            pillRow.trailingAnchor.constraint(equalTo: pillBlur.contentView.trailingAnchor, constant: -12),
            searchIcon.widthAnchor.constraint(equalToConstant: 17),
            searchIcon.heightAnchor.constraint(equalToConstant: 17)
        ])

        view.addSubview(grabHandle)
        view.addSubview(rightButtonContainer)
        view.addSubview(pillBlur)
        view.addSubview(resultsTable)
        view.addSubview(detailContainer)

        NSLayoutConstraint.activate([
            grabHandle.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            grabHandle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            grabHandle.widthAnchor.constraint(equalToConstant: 36),
            grabHandle.heightAnchor.constraint(equalToConstant: 5),

            rightButtonContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            rightButtonContainer.topAnchor.constraint(equalTo: grabHandle.bottomAnchor, constant: 6),
            rightButtonContainer.widthAnchor.constraint(equalToConstant: 40),
            rightButtonContainer.heightAnchor.constraint(equalToConstant: 40),

            pillBlur.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            pillBlur.trailingAnchor.constraint(equalTo: rightButtonContainer.leadingAnchor, constant: -8),
            pillBlur.centerYAnchor.constraint(equalTo: rightButtonContainer.centerYAnchor),
            pillBlur.heightAnchor.constraint(equalToConstant: 40),

            resultsTable.topAnchor.constraint(equalTo: pillBlur.bottomAnchor, constant: 8),
            resultsTable.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            resultsTable.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            resultsTable.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            detailContainer.topAnchor.constraint(equalTo: pillBlur.bottomAnchor, constant: 8),
            detailContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            detailContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            detailContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        updateSearchPlaceholder()
        application.regionsService.addDelegate(self)
    }

    deinit {
        application.regionsService.removeDelegate(self)
    }

    // MARK: - Search mode transitions

    @objc private func pillTapped() {
        guard !isInSearchMode else { return }
        enterSearchMode(focusTextField: true)
    }

    func enterSearchMode(focusTextField: Bool = true) {
        guard !isInSearchMode else { return }
        isInSearchMode = true

        // Swap placeholder → text field
        placeholderLabel.isHidden = true
        searchTextField.isHidden = false
        searchTextField.text = ""

        // Load recent searches immediately
        reloadSearchResults(text: "")
        resultsTable.isHidden = false

        if focusTextField {
            DispatchQueue.main.async {
                self.searchTextField.becomeFirstResponder()
                self.onSearchBecameActive?()
            }
        }
    }

    func exitSearchMode() {
        guard isInSearchMode else { return }
        isInSearchMode = false

        searchTextField.resignFirstResponder()
        searchTextField.text = ""
        searchTextField.isHidden = true
        resultsTable.isHidden = true
        searchSections = []

        placeholderLabel.isHidden = false
    }

    // MARK: - Map item detail (inline, no separate sheet)

    func showMapItemDetail(_ mapItem: MKMapItem) {
        // Remove any existing detail VC
        embeddedDetailVC?.willMove(toParent: nil)
        embeddedDetailVC?.view.removeFromSuperview()
        embeddedDetailVC?.removeFromParent()
        embeddedDetailVC = nil

        let vm = MapItemViewModel(
            mapItem: mapItem,
            application: application,
            delegate: self,
            removePinHandler: nil,
            planTripHandler: {}
        )
        let detailVC = MapItemViewController(vm)

        addChild(detailVC)
        detailVC.view.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.addSubview(detailVC.view)
        NSLayoutConstraint.activate([
            detailVC.view.topAnchor.constraint(equalTo: detailContainer.topAnchor),
            detailVC.view.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            detailVC.view.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            detailVC.view.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor)
        ])
        detailVC.didMove(toParent: self)
        embeddedDetailVC = detailVC

        // Hide search results, show detail
        resultsTable.isHidden = true
        detailContainer.isHidden = false
    }

    @objc private func dismissDetail() {
        embeddedDetailVC?.willMove(toParent: nil)
        embeddedDetailVC?.view.removeFromSuperview()
        embeddedDetailVC?.removeFromParent()
        embeddedDetailVC = nil
        detailContainer.isHidden = true

        if isInSearchMode {
            resultsTable.isHidden = false
            onSearchBecameActive?()  // snap back to medium
        }
    }

    @objc private func searchTextChanged() {
        reloadSearchResults(text: searchTextField.text ?? "")
    }

    private func reloadSearchResults(text: String) {
        searchInteractor.searchModeObjects(text: text)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.searchSections = self.searchInteractor.sections
            self.resultsTable.reloadData()
        }
    }

    // MARK: - Navigation menu

    private func makeNavigationMenu() -> UIMenu {
        let recentAction = UIAction(
            title: OBALoc("recent_stops_controller.title", value: "Recent", comment: ""),
            image: Icons.recentTabIcon
        ) { [weak self] _ in
            guard let self else { return }
            self.delegate?.mapBottomSheetDidTapRecent(self)
        }
        let bookmarksAction = UIAction(
            title: OBALoc("bookmarks_controller.title", value: "Bookmarks", comment: ""),
            image: Icons.bookmarksTabIcon
        ) { [weak self] _ in
            guard let self else { return }
            self.delegate?.mapBottomSheetDidTapBookmarks(self)
        }
        let moreAction = UIAction(
            title: OBALoc("more_controller.title", value: "More", comment: ""),
            image: Icons.moreTabIcon
        ) { [weak self] _ in
            guard let self else { return }
            self.delegate?.mapBottomSheetDidTapMore(self)
        }
        return UIMenu(children: [recentAction, bookmarksAction, moreAction])
    }

    // MARK: - Placeholder

    func updateSearchPlaceholder() {
        let text: String
        if application.features.tripPlanning == .running {
            text = OBALoc("map_floating_panel.where_are_you_going", value: "Where are you going?", comment: "")
        } else if let region = application.regionsService.currentRegion {
            text = Formatters.searchPlaceholderText(region: region)
        } else {
            text = OBALoc("map_floating_panel.search_prompt", value: "Search stops, routes, addresses", comment: "")
        }
        placeholderLabel.text = text
        searchTextField.placeholder = text
    }
}

// MARK: - UITextFieldDelegate

extension MapBottomSheetViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard let text = textField.text, !text.isEmpty else { return false }
        textField.resignFirstResponder()
        delegate?.mapBottomSheet(self, didSubmitSearch: SearchRequest(query: text, type: .address))
        return true
    }

    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        // If field is already empty, X acts as cancel to exit search mode
        if textField.text?.isEmpty == true {
            exitSearchMode()
            delegate?.mapBottomSheetDidCancelSearch(self)
            return false
        }
        // Otherwise just clear the text and reload empty results
        reloadSearchResults(text: "")
        return true
    }
}

// MARK: - SearchDelegate

extension MapBottomSheetViewController: SearchDelegate {
    var isVehicleSearchAvailable: Bool {
        application.features.obaco == .running
    }

    func performSearch(request: SearchRequest) {
        searchTextField.resignFirstResponder()
        delegate?.mapBottomSheet(self, didSubmitSearch: request)
    }

    func showMapItem(_ mapItem: MKMapItem) {
        application.userDataStore.addRecentMapItem(mapItem)
        searchTextField.resignFirstResponder()
        delegate?.mapBottomSheet(self, didSelectMapItem: mapItem)
        showMapItemDetail(mapItem)
        onDetailShown?()
    }

    func searchInteractor(_ searchInteractor: SearchInteractor, showStop stop: Stop) {
        delegate?.mapBottomSheet(self, didSelectStop: stop)
        // Don't exit search mode — let the stop VC push onto the nav stack
    }

    func searchInteractorNewResultsAvailable(_ searchInteractor: SearchInteractor) {
        reloadSearchResults(text: searchTextField.text ?? "")
    }

    func searchInteractorClearRecentSearches(_ searchInteractor: SearchInteractor) {
        let alert = UIAlertController.deletionAlert(title: Strings.clearRecentSearchesConfirmation) { [weak self] _ in
            self?.application.userDataStore.deleteAllRecentMapItems()
            self?.reloadSearchResults(text: self?.searchTextField.text ?? "")
        }
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource & Delegate

extension MapBottomSheetViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        searchSections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard section < searchSections.count else { return 0 }
        return searchSections[section].content.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard section < searchSections.count else { return nil }
        return searchSections[section].title
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        guard indexPath.section < searchSections.count,
              indexPath.row < searchSections[indexPath.section].content.count else {
            return cell
        }

        let row = searchSections[indexPath.section].content[indexPath.row]
        var config = cell.defaultContentConfiguration()

        if let attributed = row.attributedTitle {
            config.attributedText = attributed
        } else {
            config.text = row.title
        }
        config.secondaryText = row.subtitle

        switch row.icon {
        case .system(let name):
            config.image = UIImage(systemName: name)
        case .uiImage(let image):
            config.image = image
        case nil:
            config.image = nil
        }

        cell.accessoryType = row.accessory == .disclosureIndicator ? .disclosureIndicator : .none
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section < searchSections.count,
              indexPath.row < searchSections[indexPath.section].content.count else { return }

        let row = searchSections[indexPath.section].content[indexPath.row]
        row.action?()
    }
}

// MARK: - ModalDelegate

extension MapBottomSheetViewController: ModalDelegate {
    public func dismissModalController(_ controller: UIViewController) {
        dismissDetail()
    }
}

// MARK: - RegionsServiceDelegate

extension MapBottomSheetViewController: RegionsServiceDelegate {
    func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        updateSearchPlaceholder()
    }
}
