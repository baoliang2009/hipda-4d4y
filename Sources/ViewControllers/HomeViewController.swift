import UIKit

class HomeViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let contentView = UIView()

    private let headerLabel = UILabel()
    private let subtitleLabel = UILabel()

    private let hotTopicsLabel = UILabel()
    private let hotTopicsContainer = UIView()
    private let hotThreadsStackView = UIStackView()

    private let allForumsLabel = UILabel()
    private let editButton = UIButton(type: .system)
    private let forumsCollectionView: UICollectionView

    private var allForums: [Forum] = []
    private var hotThreads: [ForumThread] = []
    private var isEditMode = false

    // UserDefaults keys
    private let forumOrderKey = "forumOrder"
    private let followedForumsKey = "followedForums"

    init() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        forumsCollectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Refresh data when page becomes visible
        loadData()
    }

    private func setupUI() {
        view.backgroundColor = Theme.background

        // Scroll view with refresh control
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        // Add refresh control
        let refreshControl = UIRefreshControl()
        refreshControl.tintColor = Theme.primary
        refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        scrollView.refreshControl = refreshControl

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])

        setupHeader()
        setupHotTopics()
        setupForumsGrid()
        setupLongPressGesture()
    }

    @objc private func handleRefresh() {
        loadData()
    }

    private func setupHeader() {
        headerLabel.text = "论坛列表"
        headerLabel.font = .systemFont(ofSize: 28, weight: .bold)
        headerLabel.textColor = Theme.titleText
        contentView.addSubview(headerLabel)

        subtitleLabel.text = "浏览所有版块"
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = Theme.secondaryText
        contentView.addSubview(subtitleLabel)

        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            headerLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),

            subtitleLabel.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: headerLabel.leadingAnchor)
        ])
    }

    private func setupHotTopics() {
        hotTopicsLabel.text = "我的收藏"
        hotTopicsLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        hotTopicsLabel.textColor = Theme.titleText
        contentView.addSubview(hotTopicsLabel)

        let fireIcon = UIImageView(image: UIImage(systemName: "star.fill"))
        fireIcon.tintColor = Theme.primary
        fireIcon.contentMode = .scaleAspectFit
        contentView.addSubview(fireIcon)

        hotTopicsContainer.backgroundColor = Theme.card
        hotTopicsContainer.layer.cornerRadius = 16
        hotTopicsContainer.layer.borderColor = Theme.border.cgColor
        hotTopicsContainer.layer.borderWidth = 1
        contentView.addSubview(hotTopicsContainer)

        hotThreadsStackView.axis = .vertical
        hotThreadsStackView.spacing = 0
        hotTopicsContainer.addSubview(hotThreadsStackView)

        hotTopicsLabel.translatesAutoresizingMaskIntoConstraints = false
        fireIcon.translatesAutoresizingMaskIntoConstraints = false
        hotTopicsContainer.translatesAutoresizingMaskIntoConstraints = false
        hotThreadsStackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            hotTopicsLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 24),
            hotTopicsLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),

            fireIcon.centerYAnchor.constraint(equalTo: hotTopicsLabel.centerYAnchor),
            fireIcon.leadingAnchor.constraint(equalTo: hotTopicsLabel.trailingAnchor, constant: 8),
            fireIcon.widthAnchor.constraint(equalToConstant: 18),
            fireIcon.heightAnchor.constraint(equalToConstant: 18),

            hotTopicsContainer.topAnchor.constraint(equalTo: hotTopicsLabel.bottomAnchor, constant: 12),
            hotTopicsContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            hotTopicsContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            hotThreadsStackView.topAnchor.constraint(equalTo: hotTopicsContainer.topAnchor),
            hotThreadsStackView.leadingAnchor.constraint(equalTo: hotTopicsContainer.leadingAnchor),
            hotThreadsStackView.trailingAnchor.constraint(equalTo: hotTopicsContainer.trailingAnchor),
            hotThreadsStackView.bottomAnchor.constraint(equalTo: hotTopicsContainer.bottomAnchor)
        ])
    }

    private func setupForumsGrid() {
        allForumsLabel.text = "所有板块"
        allForumsLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        allForumsLabel.textColor = Theme.titleText
        contentView.addSubview(allForumsLabel)

        editButton.setTitle("编辑", for: .normal)
        editButton.titleLabel?.font = .systemFont(ofSize: 14)
        editButton.tintColor = Theme.primary
        editButton.addTarget(self, action: #selector(toggleEditMode), for: .touchUpInside)
        contentView.addSubview(editButton)

        forumsCollectionView.backgroundColor = .clear
        forumsCollectionView.delegate = self
        forumsCollectionView.dataSource = self
        forumsCollectionView.dragDelegate = self
        forumsCollectionView.dropDelegate = self
        forumsCollectionView.dragInteractionEnabled = true
        forumsCollectionView.register(ForumGridCell.self, forCellWithReuseIdentifier: ForumGridCell.identifier)
        forumsCollectionView.isScrollEnabled = false
        contentView.addSubview(forumsCollectionView)

        allForumsLabel.translatesAutoresizingMaskIntoConstraints = false
        editButton.translatesAutoresizingMaskIntoConstraints = false
        forumsCollectionView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            allForumsLabel.topAnchor.constraint(equalTo: hotTopicsContainer.bottomAnchor, constant: 24),
            allForumsLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),

            editButton.centerYAnchor.constraint(equalTo: allForumsLabel.centerYAnchor),
            editButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            forumsCollectionView.topAnchor.constraint(equalTo: allForumsLabel.bottomAnchor, constant: 12),
            forumsCollectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            forumsCollectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            forumsCollectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            forumsCollectionView.heightAnchor.constraint(equalToConstant: 400)
        ])
    }

    private func setupLongPressGesture() {
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        forumsCollectionView.addGestureRecognizer(longPress)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            toggleEditMode()
        }
    }

    @objc private func toggleEditMode() {
        isEditMode.toggle()
        editButton.setTitle(isEditMode ? "完成" : "编辑", for: .normal)
        forumsCollectionView.reloadData()
    }

    private func loadData() {
        // End any existing refresh
        scrollView.refreshControl?.endRefreshing()

        Task {
            do {
                // Always fetch fresh data to ensure we have latest state
                let forums = try await NetworkManager.shared.fetchForumListWithoutCache()
                print("[Home] Loaded \(forums.count) forums")
                await MainActor.run {
                    // Sort forums by custom order and followed status
                    self.allForums = self.sortForums(forums)
                    self.forumsCollectionView.reloadData()
                    self.updateCollectionViewHeight()
                    self.scrollView.refreshControl?.endRefreshing()
                }
            } catch {
                print("Failed to load forums: \(error)")
                await MainActor.run {
                    self.scrollView.refreshControl?.endRefreshing()
                }
            }
        }

        // 我的收藏（本地，无需网络）
        reloadFavorites()
    }

    /// 从本地读取收藏并刷新「我的收藏」区块
    private func reloadFavorites() {
        hotThreads = FavoriteManager.shared.favoriteThreads
        print("[Home] Showing \(hotThreads.count) favorite threads")
        updateHotThreads()
    }

    private func sortForums(_ forums: [Forum]) -> [Forum] {
        let savedOrder = UserDefaults.standard.array(forKey: forumOrderKey) as? [Int] ?? []
        let followedFids = Set(UserDefaults.standard.array(forKey: followedForumsKey) as? [Int] ?? [])

        return forums.sorted { forum1, forum2 in
            // Followed forums first
            let isFollowed1 = followedFids.contains(forum1.fid)
            let isFollowed2 = followedFids.contains(forum2.fid)

            if isFollowed1 != isFollowed2 {
                return isFollowed1
            }

            // Then by saved order
            if let index1 = savedOrder.firstIndex(of: forum1.fid),
               let index2 = savedOrder.firstIndex(of: forum2.fid) {
                return index1 < index2
            }

            // Forums with saved order come before those without
            if savedOrder.contains(forum1.fid) && !savedOrder.contains(forum2.fid) {
                return true
            }
            if !savedOrder.contains(forum1.fid) && savedOrder.contains(forum2.fid) {
                return false
            }

            // Default order by fid
            return forum1.fid < forum2.fid
        }
    }

    private func saveForumOrder() {
        let fids = allForums.map { $0.fid }
        UserDefaults.standard.set(fids, forKey: forumOrderKey)
    }

    private func toggleFollow(fid: Int) {
        var followedFids = UserDefaults.standard.array(forKey: followedForumsKey) as? [Int] ?? []

        if let index = followedFids.firstIndex(of: fid) {
            followedFids.remove(at: index)
        } else {
            followedFids.append(fid)
        }

        UserDefaults.standard.set(followedFids, forKey: followedForumsKey)

        // Re-sort and reload
        allForums = sortForums(allForums)
        forumsCollectionView.reloadData()
        updateCollectionViewHeight()
    }

    private func isFollowed(fid: Int) -> Bool {
        let followedFids = UserDefaults.standard.array(forKey: followedForumsKey) as? [Int] ?? []
        return followedFids.contains(fid)
    }

    private func updateHotThreads() {
        // Clear existing views
        hotThreadsStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // 空状态
        guard !hotThreads.isEmpty else {
            hotThreadsStackView.addArrangedSubview(makeEmptyFavoritesView())
            return
        }

        for (index, thread) in hotThreads.enumerated() {
            let threadView = createHotThreadRow(
                index: index + 1,
                title: thread.title,
                views: thread.viewCount,
                replies: thread.replyCount,
                thread: thread
            )
            hotThreadsStackView.addArrangedSubview(threadView)

            if index < hotThreads.count - 1 {
                let divider = UIView()
                divider.backgroundColor = Theme.border
                divider.translatesAutoresizingMaskIntoConstraints = false
                divider.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
                hotThreadsStackView.addArrangedSubview(divider)
            }
        }
    }

    private func makeEmptyFavoritesView() -> UIView {
        let container = UIView()
        container.backgroundColor = Theme.card

        let label = UILabel()
        label.text = "还没有收藏的帖子\n在帖子页点右上角 ☆ 即可收藏"
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 13)
        label.textColor = Theme.secondaryText
        container.addSubview(label)

        container.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 88),
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20)
        ])
        return container
    }

    private func createHotThreadRow(index: Int, title: String, views: Int, replies: Int, thread: ForumThread?) -> UIView {
        let container = UIView()
        container.backgroundColor = Theme.card

        let indexView = UIView()
        indexView.backgroundColor = Theme.primary.withAlphaComponent(0.15)
        indexView.layer.cornerRadius = 8
        container.addSubview(indexView)

        let indexLabel = UILabel()
        indexLabel.text = "\(index)"
        indexLabel.font = .systemFont(ofSize: 14, weight: .bold)
        indexLabel.textColor = Theme.primary
        indexLabel.textAlignment = .center
        indexView.addSubview(indexLabel)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = Theme.titleText
        titleLabel.numberOfLines = 2
        container.addSubview(titleLabel)

        let statsLabel = UILabel()
        statsLabel.text = "\(views) 浏览 · \(replies) 回复"
        statsLabel.font = .systemFont(ofSize: 12)
        statsLabel.textColor = Theme.secondaryText
        container.addSubview(statsLabel)

        let arrowIcon = UIImageView(image: UIImage(systemName: "chevron.right"))
        arrowIcon.tintColor = Theme.secondaryText
        arrowIcon.contentMode = .scaleAspectFit
        container.addSubview(arrowIcon)

        container.translatesAutoresizingMaskIntoConstraints = false
        indexView.translatesAutoresizingMaskIntoConstraints = false
        indexLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        arrowIcon.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 70),

            indexView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            indexView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            indexView.widthAnchor.constraint(equalToConstant: 32),
            indexView.heightAnchor.constraint(equalToConstant: 32),

            indexLabel.centerXAnchor.constraint(equalTo: indexView.centerXAnchor),
            indexLabel.centerYAnchor.constraint(equalTo: indexView.centerYAnchor),

            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: indexView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: arrowIcon.leadingAnchor, constant: -8),

            statsLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            statsLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),

            arrowIcon.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            arrowIcon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            arrowIcon.widthAnchor.constraint(equalToConstant: 16),
            arrowIcon.heightAnchor.constraint(equalToConstant: 16)
        ])

        // Add tap gesture if thread is available
        if let thread = thread {
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(hotThreadTapped(_:)))
            container.addGestureRecognizer(tapGesture)
            container.tag = hotThreads.firstIndex(where: { $0.tid == thread.tid }) ?? 0
            container.isUserInteractionEnabled = true
        }

        return container
    }

    @objc private func hotThreadTapped(_ gesture: UITapGestureRecognizer) {
        guard let view = gesture.view else { return }
        let index = view.tag
        guard index < hotThreads.count else { return }

        let thread = hotThreads[index]
        print("[Home] Tapped hot thread: tid=\(thread.tid), title=\(thread.title)")

        let threadDetailVC = ThreadDetailViewController(thread: thread)
        navigationController?.pushViewController(threadDetailVC, animated: true)
    }

    private func updateCollectionViewHeight() {
        let itemsPerRow: CGFloat = 2
        let spacing: CGFloat = 12
        let totalSpacing = spacing * (itemsPerRow - 1)
        let availableWidth = view.bounds.width - 40 - totalSpacing
        let itemWidth = availableWidth / itemsPerRow
        let rows = ceil(CGFloat(allForums.count) / itemsPerRow)
        let height = rows * (itemWidth * 0.9) + (rows - 1) * spacing

        forumsCollectionView.constraints.forEach { constraint in
            if constraint.firstAttribute == .height {
                constraint.constant = max(height, 200)
            }
        }
    }
}

// MARK: - UICollectionViewDataSource & UICollectionViewDelegate

extension HomeViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return allForums.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ForumGridCell.identifier, for: indexPath) as? ForumGridCell else {
            return UICollectionViewCell()
        }
        let forum = allForums[indexPath.item]
        cell.configure(with: forum, isFollowed: isFollowed(fid: forum.fid), isEditMode: isEditMode)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let itemsPerRow: CGFloat = 2
        let spacing: CGFloat = 12
        let totalSpacing = spacing * (itemsPerRow - 1)
        let availableWidth = collectionView.bounds.width - totalSpacing
        let itemWidth = availableWidth / itemsPerRow
        return CGSize(width: itemWidth, height: itemWidth * 0.9)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if isEditMode {
            // In edit mode, tap toggles follow status
            let forum = allForums[indexPath.item]
            toggleFollow(fid: forum.fid)
        } else {
            let forum = allForums[indexPath.item]
            let threadListVC = ThreadListViewController(forum: forum)
            navigationController?.pushViewController(threadListVC, animated: true)
        }
    }
}

// MARK: - UICollectionViewDragDelegate

extension HomeViewController: UICollectionViewDragDelegate {
    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        let forum = allForums[indexPath.item]
        let itemProvider = NSItemProvider(object: "\(forum.fid)" as NSString)
        let dragItem = UIDragItem(itemProvider: itemProvider)
        dragItem.localObject = forum
        return [dragItem]
    }
}

// MARK: - UICollectionViewDropDelegate

extension HomeViewController: UICollectionViewDropDelegate {
    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        if collectionView.hasActiveDrag {
            return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
        }
        return UICollectionViewDropProposal(operation: .forbidden)
    }

    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard let destinationIndexPath = coordinator.destinationIndexPath,
              let item = coordinator.items.first,
              let sourceIndexPath = item.sourceIndexPath else {
            return
        }

        collectionView.performBatchUpdates {
            let forum = allForums.remove(at: sourceIndexPath.item)
            allForums.insert(forum, at: destinationIndexPath.item)
            collectionView.moveItem(at: sourceIndexPath, to: destinationIndexPath)
        }

        // Save new order
        saveForumOrder()

        coordinator.drop(item.dragItem, toItemAt: destinationIndexPath)

        // Reload to update edit mode state
        forumsCollectionView.reloadData()
    }
}

// MARK: - LoginViewControllerDelegate

extension HomeViewController: LoginViewControllerDelegate {
    func loginViewControllerDidLogin(_ controller: LoginViewController) {
        print("[Home] Login completed, refreshing forum list...")
        loadData()
    }

    func loginViewControllerDidLoginWithForumData(_ controller: LoginViewController, forums: [Forum]) {
        print("[Home] Login with forum data completed, refreshing...")
        // Use the forum data passed from login if available
        self.allForums = self.sortForums(forums)
        self.forumsCollectionView.reloadData()
        self.updateCollectionViewHeight()
    }

    func loginViewControllerDidCancel(_ controller: LoginViewController) {
        // Nothing to do
    }
}

// MARK: - Forum Grid Cell

class ForumGridCell: UICollectionViewCell {

    static let identifier = "ForumGridCell"

    private let containerView = UIView()
    private let iconView = UIImageView()
    private let nameLabel = UILabel()
    private let descLabel = UILabel()
    private let statsLabel = UILabel()
    private let followedBadge = UIView()
    private let followedIcon = UIImageView()
    private let editOverlay = UIView()
    private let dragHandle = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        containerView.backgroundColor = Theme.card
        containerView.layer.cornerRadius = 16
        containerView.layer.borderColor = Theme.border.cgColor
        containerView.layer.borderWidth = 1
        contentView.addSubview(containerView)

        iconView.backgroundColor = Theme.primary.withAlphaComponent(0.15)
        iconView.tintColor = Theme.primary
        iconView.contentMode = .center
        iconView.layer.cornerRadius = 12
        containerView.addSubview(iconView)

        nameLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        nameLabel.textColor = Theme.titleText
        nameLabel.numberOfLines = 1
        containerView.addSubview(nameLabel)

        descLabel.font = .systemFont(ofSize: 11)
        descLabel.textColor = Theme.secondaryText
        descLabel.numberOfLines = 2
        containerView.addSubview(descLabel)

        statsLabel.font = .systemFont(ofSize: 10)
        statsLabel.textColor = Theme.secondaryText
        containerView.addSubview(statsLabel)

        // Followed badge
        followedBadge.backgroundColor = Theme.primary.withAlphaComponent(0.15)
        followedBadge.layer.cornerRadius = 10
        followedBadge.isHidden = true
        containerView.addSubview(followedBadge)

        followedIcon.image = UIImage(systemName: "star.fill")
        followedIcon.tintColor = Theme.primary
        followedIcon.contentMode = .scaleAspectFit
        followedBadge.addSubview(followedIcon)

        // Edit overlay
        editOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        editOverlay.layer.cornerRadius = 16
        editOverlay.isHidden = true
        contentView.addSubview(editOverlay)

        dragHandle.image = UIImage(systemName: "line.3.horizontal")
        dragHandle.tintColor = .white
        dragHandle.contentMode = .scaleAspectFit
        dragHandle.isHidden = true
        editOverlay.addSubview(dragHandle)

        containerView.translatesAutoresizingMaskIntoConstraints = false
        iconView.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        followedBadge.translatesAutoresizingMaskIntoConstraints = false
        followedIcon.translatesAutoresizingMaskIntoConstraints = false
        editOverlay.translatesAutoresizingMaskIntoConstraints = false
        dragHandle.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            iconView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            iconView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),

            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),

            descLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            descLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            descLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),

            statsLabel.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 8),
            statsLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            statsLabel.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -12),

            // Followed badge
            followedBadge.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            followedBadge.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            followedBadge.widthAnchor.constraint(equalToConstant: 20),
            followedBadge.heightAnchor.constraint(equalToConstant: 20),

            followedIcon.centerXAnchor.constraint(equalTo: followedBadge.centerXAnchor),
            followedIcon.centerYAnchor.constraint(equalTo: followedBadge.centerYAnchor),
            followedIcon.widthAnchor.constraint(equalToConstant: 12),
            followedIcon.heightAnchor.constraint(equalToConstant: 12),

            // Edit overlay
            editOverlay.topAnchor.constraint(equalTo: contentView.topAnchor),
            editOverlay.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            editOverlay.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            editOverlay.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            dragHandle.centerXAnchor.constraint(equalTo: editOverlay.centerXAnchor),
            dragHandle.centerYAnchor.constraint(equalTo: editOverlay.centerYAnchor),
            dragHandle.widthAnchor.constraint(equalToConstant: 24),
            dragHandle.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    func configure(with forum: Forum, isFollowed: Bool, isEditMode: Bool) {
        nameLabel.text = forum.name
        descLabel.text = forum.description.isEmpty ? "暂无描述" : forum.description
        statsLabel.text = "\(forum.threadCount) 话题 · \(forum.postCount) 帖子"
        iconView.image = UIImage(systemName: "bubble.left.and.bubble.right.fill")

        // Show followed badge if followed
        followedBadge.isHidden = !isFollowed

        // Show edit overlay in edit mode
        editOverlay.isHidden = !isEditMode
        dragHandle.isHidden = !isEditMode

        // Adjust border for edit mode
        containerView.layer.borderWidth = isEditMode ? 2 : 1
        containerView.layer.borderColor = isEditMode ? Theme.primary.cgColor : Theme.border.cgColor
    }
}
