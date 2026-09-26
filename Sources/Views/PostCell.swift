import UIKit
import SDWebImage

protocol PostCellDelegate: AnyObject {
    func postCellDidTapReply(_ cell: PostCell, post: ForumPost)
}

class PostCell: UITableViewCell {

    static let identifier = "PostCell"

    weak var delegate: PostCellDelegate?

    private let containerView = UIView()
    private let avatarView = UIImageView()
    private let authorNameLabel = UILabel()
    private let pinnedBadge = UIView()
    private let pinnedLabel = UILabel()
    private let pinIcon = UIImageView()
    private let dateLabel = UILabel()
    private let floorLabel = UILabel()  // Shows floor number like "1楼"
    private let titleLabel = UILabel()
    let contentLabel = UILabel()  // Internal for ContentFormatter extension
    private let statsContainer = UIView()
    private let replyCountView = UIStackView()
    private let replyIcon = UIImageView()
    private let replyLabel = UILabel()
    private let viewCountView = UIStackView()
    private let viewIcon = UIImageView()
    private let viewLabel = UILabel()
    private let replyButton = UIButton(type: .system)  // Reply button for each post
    private let imagesContainer = UIView()
    private let imagesStackView = UIStackView()

    private var imageViews: [UIImageView] = []
    private var currentPost: ForumPost?
    private var currentImageURLs: [String] = []

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        selectionStyle = .none
        backgroundColor = Theme.background

        // Container card
        containerView.backgroundColor = Theme.card
        containerView.layer.cornerRadius = 16
        containerView.layer.borderColor = Theme.border.cgColor
        containerView.layer.borderWidth = 1

        // Avatar
        avatarView.backgroundColor = Theme.muted
        avatarView.contentMode = .scaleAspectFill
        avatarView.layer.cornerRadius = 20
        avatarView.layer.masksToBounds = true
        avatarView.layer.borderColor = Theme.border.cgColor
        avatarView.layer.borderWidth = 2
        avatarView.image = UIImage(systemName: "person.circle.fill")
        avatarView.tintColor = Theme.secondaryText

        // Author name
        authorNameLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        authorNameLabel.textColor = Theme.titleText

        // Pinned badge
        pinnedBadge.backgroundColor = Theme.primary.withAlphaComponent(0.12)
        pinnedBadge.layer.cornerRadius = 6

        pinIcon.image = UIImage(systemName: "pin.fill")
        pinIcon.tintColor = Theme.primary
        pinIcon.contentMode = .scaleAspectFit

        pinnedLabel.text = "置顶"
        pinnedLabel.font = .systemFont(ofSize: 12, weight: .medium)
        pinnedLabel.textColor = Theme.primary

        // Date
        dateLabel.font = .systemFont(ofSize: 13)
        dateLabel.textColor = Theme.secondaryText

        // Floor label
        floorLabel.font = .systemFont(ofSize: 12, weight: .medium)
        floorLabel.textColor = Theme.secondaryText
        floorLabel.textAlignment = .right

        // Title
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = Theme.titleText
        titleLabel.numberOfLines = 2

        // Content preview
        contentLabel.font = .systemFont(ofSize: 15)
        contentLabel.textColor = Theme.bodyText
        contentLabel.numberOfLines = 0

        // Stats container
        replyIcon.image = UIImage(systemName: "message-square")
        replyIcon.tintColor = Theme.secondaryText
        replyIcon.contentMode = .scaleAspectFit

        replyLabel.font = .systemFont(ofSize: 13)
        replyLabel.textColor = Theme.secondaryText

        replyCountView.axis = .horizontal
        replyCountView.spacing = 4
        replyCountView.alignment = .center
        replyCountView.addArrangedSubview(replyIcon)
        replyCountView.addArrangedSubview(replyLabel)

        viewIcon.image = UIImage(systemName: "eye")
        viewIcon.tintColor = Theme.secondaryText
        viewIcon.contentMode = .scaleAspectFit

        viewLabel.font = .systemFont(ofSize: 13)
        viewLabel.textColor = Theme.secondaryText

        viewCountView.axis = .horizontal
        viewCountView.spacing = 4
        viewCountView.alignment = .center
        viewCountView.addArrangedSubview(viewIcon)
        viewCountView.addArrangedSubview(viewLabel)

        // Reply button
        replyButton.setTitle("回复", for: .normal)
        replyButton.setTitleColor(Theme.primary, for: .normal)
        replyButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        replyButton.addTarget(self, action: #selector(replyTapped), for: .touchUpInside)

        // Images container and stack view
        imagesStackView.axis = .vertical
        imagesStackView.spacing = 8
        imagesStackView.distribution = .fill
        imagesContainer.addSubview(imagesStackView)
        imagesContainer.isHidden = true

        // Add subviews
        contentView.addSubview(containerView)
        containerView.addSubview(avatarView)
        containerView.addSubview(authorNameLabel)
        containerView.addSubview(pinnedBadge)
        pinnedBadge.addSubview(pinIcon)
        pinnedBadge.addSubview(pinnedLabel)
        containerView.addSubview(dateLabel)
        containerView.addSubview(floorLabel)
        containerView.addSubview(titleLabel)
        containerView.addSubview(contentLabel)
        containerView.addSubview(statsContainer)
        statsContainer.addSubview(replyCountView)
        statsContainer.addSubview(viewCountView)
        containerView.addSubview(replyButton)
        containerView.addSubview(imagesContainer)

        setupConstraints()
    }

    private func setupConstraints() {
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        authorNameLabel.translatesAutoresizingMaskIntoConstraints = false
        pinnedBadge.translatesAutoresizingMaskIntoConstraints = false
        pinIcon.translatesAutoresizingMaskIntoConstraints = false
        pinnedLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        floorLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentLabel.translatesAutoresizingMaskIntoConstraints = false
        statsContainer.translatesAutoresizingMaskIntoConstraints = false
        replyCountView.translatesAutoresizingMaskIntoConstraints = false
        replyIcon.translatesAutoresizingMaskIntoConstraints = false
        replyLabel.translatesAutoresizingMaskIntoConstraints = false
        viewCountView.translatesAutoresizingMaskIntoConstraints = false
        viewIcon.translatesAutoresizingMaskIntoConstraints = false
        viewLabel.translatesAutoresizingMaskIntoConstraints = false
        replyButton.translatesAutoresizingMaskIntoConstraints = false
        imagesContainer.translatesAutoresizingMaskIntoConstraints = false
        imagesStackView.translatesAutoresizingMaskIntoConstraints = false
        containerView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // Container - pinned to content view
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),

            // Avatar
            avatarView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            avatarView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            avatarView.widthAnchor.constraint(equalToConstant: 40),
            avatarView.heightAnchor.constraint(equalToConstant: 40),

            // Author name
            authorNameLabel.topAnchor.constraint(equalTo: avatarView.topAnchor, constant: 2),
            authorNameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),

            // Floor label (right side)
            floorLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            floorLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),

            // Pinned badge
            pinnedBadge.centerYAnchor.constraint(equalTo: authorNameLabel.centerYAnchor),
            pinnedBadge.leadingAnchor.constraint(equalTo: authorNameLabel.trailingAnchor, constant: 8),
            pinnedBadge.heightAnchor.constraint(equalToConstant: 22),

            pinIcon.leadingAnchor.constraint(equalTo: pinnedBadge.leadingAnchor, constant: 6),
            pinIcon.centerYAnchor.constraint(equalTo: pinnedBadge.centerYAnchor),
            pinIcon.widthAnchor.constraint(equalToConstant: 12),
            pinIcon.heightAnchor.constraint(equalToConstant: 12),

            pinnedLabel.leadingAnchor.constraint(equalTo: pinIcon.trailingAnchor, constant: 2),
            pinnedLabel.trailingAnchor.constraint(equalTo: pinnedBadge.trailingAnchor, constant: -6),
            pinnedLabel.centerYAnchor.constraint(equalTo: pinnedBadge.centerYAnchor),

            // Date
            dateLabel.topAnchor.constraint(equalTo: authorNameLabel.bottomAnchor, constant: 4),
            dateLabel.leadingAnchor.constraint(equalTo: authorNameLabel.leadingAnchor),

            // Title - below avatar
            titleLabel.topAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),

            // Content - below title
            contentLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            contentLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            contentLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),

            // Stats container - below content
            statsContainer.topAnchor.constraint(equalTo: contentLabel.bottomAnchor, constant: 14),
            statsContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            statsContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            statsContainer.heightAnchor.constraint(equalToConstant: 24),

            replyCountView.leadingAnchor.constraint(equalTo: statsContainer.leadingAnchor),
            replyCountView.centerYAnchor.constraint(equalTo: statsContainer.centerYAnchor),

            replyIcon.widthAnchor.constraint(equalToConstant: 16),
            replyIcon.heightAnchor.constraint(equalToConstant: 16),

            viewCountView.leadingAnchor.constraint(equalTo: replyCountView.trailingAnchor, constant: 16),
            viewCountView.centerYAnchor.constraint(equalTo: statsContainer.centerYAnchor),

            viewIcon.widthAnchor.constraint(equalToConstant: 16),
            viewIcon.heightAnchor.constraint(equalToConstant: 16),

            // Reply button
            replyButton.trailingAnchor.constraint(equalTo: statsContainer.trailingAnchor),
            replyButton.centerYAnchor.constraint(equalTo: statsContainer.centerYAnchor),

            // Images container - below stats
            imagesContainer.topAnchor.constraint(equalTo: statsContainer.bottomAnchor, constant: 12),
            imagesContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            imagesContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            imagesContainer.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16),

            // Images stack view fills container
            imagesStackView.topAnchor.constraint(equalTo: imagesContainer.topAnchor),
            imagesStackView.leadingAnchor.constraint(equalTo: imagesContainer.leadingAnchor),
            imagesStackView.trailingAnchor.constraint(equalTo: imagesContainer.trailingAnchor),
            imagesStackView.bottomAnchor.constraint(equalTo: imagesContainer.bottomAnchor)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // 取消进行中的图片下载，避免复用时把上一条 cell 的图片贴到这条上，
        // 以及快速滚动时的无谓下载
        avatarView.sd_cancelCurrentImageLoad()
        avatarView.image = UIImage(systemName: "person.circle.fill")
        for imgView in imageViews {
            imgView.sd_cancelCurrentImageLoad()
            imgView.removeFromSuperview()
        }
        imageViews.removeAll()
        contentLabel.attributedText = nil
        titleLabel.text = nil
    }

    func configure(with post: ForumPost) {
        authorNameLabel.text = post.author
        dateLabel.text = post.postDate

        // Floor label
        floorLabel.text = "#\(post.floorNumber)楼"

        // Title
        let title = post.title ?? ""
        titleLabel.text = title.isEmpty ? "" : title
        titleLabel.isHidden = title.isEmpty

        // Content with proper formatting
        let contentText = post.content
        setFormattedContent(contentText)

        // Hide pinned badge by default
        pinnedBadge.isHidden = true

        // Stats
        replyLabel.text = "\(post.floorNumber)"
        viewLabel.text = "\(post.viewCount)"

        // Store post for reply action
        currentPost = post

        // Load avatar image
        if let avatarURLString = post.authorAvatar, let avatarURL = URL(string: avatarURLString) {
            avatarView.sd_setImage(with: avatarURL, placeholderImage: UIImage(systemName: "person.circle.fill"))
        } else {
            avatarView.image = UIImage(systemName: "person.circle.fill")
        }

        // Configure images
        configureImages(post.images)
    }

    func configure(with thread: ForumThread) {
        authorNameLabel.text = thread.author
        dateLabel.text = thread.lastPostDate
        titleLabel.text = thread.title
        titleLabel.isHidden = false

        replyLabel.text = "\(thread.replyCount)"
        viewLabel.text = "\(thread.viewCount)"

        avatarView.image = UIImage(systemName: "person.circle.fill")
        pinnedBadge.isHidden = true

        configureImages([])
    }

    private func configureImages(_ imageURLs: [String]) {
        // Remove existing image views
        for imgView in imageViews {
            imgView.removeFromSuperview()
        }
        imageViews.removeAll()
        currentImageURLs = imageURLs

        // Remove existing arranged subviews
        for view in imagesStackView.arrangedSubviews {
            imagesStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if imageURLs.isEmpty {
            imagesContainer.isHidden = true
            return
        }

        imagesContainer.isHidden = false

        for (index, imageURL) in imageURLs.prefix(3).enumerated() {
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFill
            imageView.backgroundColor = Theme.muted
            imageView.layer.cornerRadius = 8
            imageView.clipsToBounds = true
            imageView.isUserInteractionEnabled = true
            imageView.tag = index

            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(imageTapped(_:)))
            imageView.addGestureRecognizer(tapGesture)

            imageView.translatesAutoresizingMaskIntoConstraints = false

            // Fixed height for images
            imageView.heightAnchor.constraint(equalToConstant: 180).isActive = true

            // Use optimized image loading with progress indicator
            imageView.loadForumImage(from: imageURL, placeholder: nil) { [weak imageView] image, error in
                if error != nil {
                    // Show placeholder on error
                    imageView?.backgroundColor = Theme.muted
                }
            }

            imagesStackView.addArrangedSubview(imageView)
            imageViews.append(imageView)
        }
    }

    @objc private func replyTapped() {
        guard let post = currentPost else { return }
        delegate?.postCellDidTapReply(self, post: post)
    }

    @objc private func imageTapped(_ gesture: UITapGestureRecognizer) {
        guard let imageView = gesture.view as? UIImageView else { return }
        let tappedIndex = imageView.tag

        // Get the image URL for full resolution loading
        if tappedIndex < currentImageURLs.count {
            let imageURL = currentImageURLs[tappedIndex]
            showFullScreenImage(withURL: imageURL, placeholder: imageView.image)
        } else if let image = imageView.image {
            // Fallback to thumbnail
            showFullScreenImage(image)
        }
    }

    private func showFullScreenImage(withURL url: String, placeholder: UIImage?) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return }

        let fullScreenVC = FullScreenImageViewController(imageURL: url)
        fullScreenVC.modalPresentationStyle = .fullScreen
        window.rootViewController?.present(fullScreenVC, animated: true)
    }

    private func showFullScreenImage(_ image: UIImage) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return }

        let fullScreenVC = FullScreenImageViewController(image: image)
        fullScreenVC.modalPresentationStyle = .fullScreen
        window.rootViewController?.present(fullScreenVC, animated: true)
    }
}
