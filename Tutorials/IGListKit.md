# Creating a new IGListKit-based View Controller

## Create a `UIViewController`

Make the controller conform to `AppContext` and `ListAdapterDataSource`:

    class ExampleViewController: UIViewController, AppContext, ListAdapterDataSource {
        
        public let application: Application
        
        // MARK: - IGListKit

        func objects(for listAdapter: ListAdapter) -> [ListDiffable] {
            return ["One", "Two", "Three", "Four"] as [ListDiffable]
        }

        func listAdapter(_ listAdapter: ListAdapter, sectionControllerFor object: Any) -> ListSectionController {
            return defaultSectionController(for: object)
        }

        func emptyView(for listAdapter: ListAdapter) -> UIView? {
            return nil
        }
    }

## Add a collection controller

Use the `CollectionController` class to easily create a `UICollectionView` configured for use with IGListKit.

    // MARK: - Collection Controller

    private lazy var collectionController = CollectionController(application: application, dataSource: self)

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = ThemeColors.shared.systemBackground
        addChildController(collectionController)
        collectionController.view.pinToSuperview(.edges)
    }

### Refresh Control

You can include a refresh control with your collection view, if that matches your expectations for the UI you are building.

    // MARK: - Collection Controller

    private lazy var collectionController = CollectionController(application: application, dataSource: self)

    private lazy var refreshControl: UIRefreshControl = {
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(reloadData), for: .valueChanged)
        return refresh
    }()
    
    @objc private func reloadData() {
        // todo - reload data
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = ThemeColors.shared.systemBackground
        addChildController(collectionController)
        collectionController.view.pinToSuperview(.edges)
        collectionController.collectionView.addSubview(refreshControl)
    }
    

# IGListKit Cells

## The Easy Option

Just use `BaseSelfSizingTableCell`, which is a collection view cell meant for subclassing. It provides self-sizing support, a bottom separator, and highlighting on touch.

## A Full Featured Cell

Here's an example of a collection cell that implements self-sizing, a bottom separator, and highlighting on touch.

    class MyCell: SelfSizingCollectionCell, Separated {

        private let textLabel: UILabel = {
            let label = UILabel.autolayoutNew()
            label.font = UIFont.preferredFont(forTextStyle: .body)
            return label
        }()

        override func prepareForReuse() {
            super.prepareForReuse()

            textLabel.text = nil
        }

        override var isHighlighted: Bool {
            didSet {
                contentView.backgroundColor = isHighlighted ? ThemeColors.shared.highlightedBackgroundColor : nil
            }
        }

        let separator = tableCellSeparatorLayer()

        override func layoutSubviews() {
            super.layoutSubviews()
            layoutSeparator()
        }

        override init(frame: CGRect) {
            super.init(frame: frame)

            contentView.backgroundColor = ThemeColors.shared.systemBackground

            contentView.layer.addSublayer(separator)
            
            contentView.addSubview(textLabel)
            textLabel.pinToSuperview(.layoutMargins)
        }

        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }


## Separated

`Separated` is a protocol implemented by `UICollectionViewCell`s that allows them to render a bottom separator. Implementing `Separated` requires the following:

    class MyCell: UICollectionViewCell, Separated {

        let separator = tableCellSeparatorLayer()

        override func layoutSubviews() {
            super.layoutSubviews()
            layoutSeparator()
        }

        override init(frame: CGRect) {
            super.init(frame: frame)

            contentView.layer.addSublayer(separator)
        }
    }

1. Make your cell conform to the `Separated` protocol
2. Create a `separator` property and add it as a sublayer of `contentView.layer`
3. Call `layoutSeparator()` in `layoutSubviews()`

## Auto Layout and Self-Sizing Cells

Creating a `UICollectionViewCell` that correctly interacts with Auto Layout requires you to either conform to the `SelfSizing` protocol, or subclass `SelfSizingCollectionCell`, which already conforms to `SelfSizing`. Supporting Auto Layout with `SelfSizingCollectionCell` simply requires you to create a subclass, add your views to the cell's `contentView`, and make sure you always set `translatesAutoresizingMaskIntoConstraints` to `false`. In other words: there's no magic.

Conforming to `SelfSizing` is slightly more complicated, but it's not difficult. The implementation of `SelfSizingCollectionCell` shows you exactly how to accomplish this task. I recommend copying that class and using that as the basis for your self-sizing cell when `SelfSizingCollectionCell` won't suffice.

## Highlighting

It's important for any collection view cells that the user can interact with to respond to touches with a highlight. Supporting highlighting works as follows:

    override var isHighlighted: Bool {
        didSet {
            contentView.backgroundColor = isHighlighted ? ThemeColors.shared.highlightedBackgroundColor : nil
        }
    }
    
# Adding New Content Types to IGListKit

To add a new content type to IGListKit, you must add three classes:

* Data class
* Section controller class 
* Cell class

and then add an entry for the data class and section controller to `ListAdapterDataSource.defaultSectionController(:)`, which is in the OBAKit project file `ListKitExtensions.swift`.

See below for a full, albeit somewhat contrived implementation of these three classes:

    final class LabelSectionData: NSObject, ListDiffable {
        let text: String
    
        init(text: String) {
            self.text = text
        }
    
        func diffIdentifier() -> NSObjectProtocol {
            return self.text as NSObjectProtocol
        }

        func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
            guard let rhs = object as? LabelSectionData else {
                return false
            }

            return text == rhs.text
        }
    }

    final class LabelSectionController: OBAListSectionController<LabelSectionData> {
        override func sizeForItem(at index: Int) -> CGSize {
            return CGSize(width: collectionContext!.containerSize.width, height: 40)
        }

        override func cellForItem(at index: Int) -> UICollectionViewCell {
            guard let cell = collectionContext?.dequeueReusableCell(of: LabelCell.self, for: self, at: index) as? LabelCell else {
                fatalError()
            }
            cell.object = object
            return cell
        }
    }

    final class LabelCell: SelfSizingCollectionCell, Separated {
        let label: UILabel = {
            let label = UILabel.autolayoutNew()
            label.font = UIFont.preferredFont(forTextStyle: .body)
            label.backgroundColor = .clear
            label.numberOfLines = 0
            return label
        }()

        let separator = tableCellSeparatorLayer()

        var object: LabelSectionData? {
            didSet {
                label.text = object?.text
            }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            contentView.backgroundColor = ThemeColors.shared.systemBackground

            contentView.layer.addSublayer(separator)
        
            contentView.addSubview(textLabel)
            textLabel.pinToSuperview(.layoutMargins)
        }

        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            layoutSeparator()
        }

        override var isHighlighted: Bool {
            didSet {
                contentView.backgroundColor = isHighlighted ? ThemeColors.shared.highlightedBackgroundColor : nil
            }
        }
    }

