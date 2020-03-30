# Creating a new IGListKit UI

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

Optionally, you can include a refresh control, too, if that matches your expectations for this UI.

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

## Display the collection controller

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = ThemeColors.shared.systemBackground
        addChildController(collectionController)
        collectionController.view.pinToSuperview(.edges)
        collectionController.collectionView.addSubview(refreshControl)
    }

