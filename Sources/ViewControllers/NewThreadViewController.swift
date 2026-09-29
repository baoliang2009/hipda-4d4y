import UIKit
import PhotosUI

protocol NewThreadViewControllerDelegate: AnyObject {
    func newThreadViewControllerDidPost(_ controller: NewThreadViewController)
}

/// 发布新主题。
///
/// 已从 WKWebView 方案改为原生：取发帖表单、上传图片、提交发帖全部走 URLSession。
/// 旧方案用隐藏 WKWebView 打开 post.php 取 formhash/posttime/uploadHash 再 form.submit()，
/// 但 WKWebView 会被 Cloudflare Turnstile 拦死（见 CLAUDE.md），表单数据取不到、帖子发不出，
/// 图片也因为 uploadHash 拿不到而永远走"以纯文本发帖"分支。现在全部原生化。
class NewThreadViewController: UIViewController {

    weak var delegate: NewThreadViewControllerDelegate?

    private let fid: Int
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let titleTextField = UITextField()
    private let contentTextView = UITextView()
    private let typeidButton = UIButton(type: .system)
    private let tagsTextField = UITextField()
    private let attachmentButton = UIButton(type: .system)
    private let attachmentCollectionView: UICollectionView
    private let postButton = UIButton(type: .system)
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    private var formInfo: NetworkManager.PostFormInfo?
    private var typeid: Int = 0
    private var isSubmitting = false

    private var selectedImages: [UIImage] = []
    private var typeidOptions: [(id: Int, name: String)] = []

    init(fid: Int) {
        self.fid = fid

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 80, height: 80)
        layout.minimumInteritemSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        self.attachmentCollectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)

        super.init(nibName: nil, bundle: nil)

        let options = ForumManager.shared.getTypeidOptions(for: fid)
        self.typeidOptions = options.map { (id: $0.id, name: $0.name) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadForm()
    }

    private func setupUI() {
        title = "发布新主题"
        view.backgroundColor = Theme.background

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        navigationItem.leftBarButtonItem?.tintColor = Theme.primary

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

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

        setupTypeidButton()
        setupTitleField()
        setupTagsField()
        setupContentField()
        setupAttachmentSection()
        setupPostButton()
    }

    private func setupTypeidButton() {
        let label = UILabel()
        label.text = "分类"
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = Theme.secondaryText

        typeidButton.setTitle("选择分类", for: .normal)
        typeidButton.setTitleColor(Theme.foreground, for: .normal)
        typeidButton.backgroundColor = Theme.muted
        typeidButton.layer.cornerRadius = 8
        typeidButton.contentHorizontalAlignment = .left
        typeidButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        typeidButton.addTarget(self, action: #selector(typeidButtonTapped), for: .touchUpInside)

        contentView.addSubview(label)
        contentView.addSubview(typeidButton)

        label.translatesAutoresizingMaskIntoConstraints = false
        typeidButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            typeidButton.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
            typeidButton.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            typeidButton.trailingAnchor.constraint(equalTo: label.trailingAnchor),
            typeidButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func setupTitleField() {
        let label = UILabel()
        label.text = "标题"
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = Theme.secondaryText

        titleTextField.borderStyle = .roundedRect
        titleTextField.placeholder = "输入帖子标题"
        titleTextField.backgroundColor = Theme.muted
        titleTextField.textColor = Theme.foreground
        titleTextField.attributedPlaceholder = NSAttributedString(
            string: "输入帖子标题",
            attributes: [.foregroundColor: Theme.secondaryText]
        )

        contentView.addSubview(label)
        contentView.addSubview(titleTextField)

        label.translatesAutoresizingMaskIntoConstraints = false
        titleTextField.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: typeidButton.bottomAnchor, constant: 20),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            titleTextField.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
            titleTextField.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            titleTextField.trailingAnchor.constraint(equalTo: label.trailingAnchor),
            titleTextField.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func setupTagsField() {
        let label = UILabel()
        label.text = "标签 (用逗号或空格隔开，最多5个)"
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = Theme.secondaryText

        tagsTextField.borderStyle = .roundedRect
        tagsTextField.placeholder = "标签1, 标签2, 标签3"
        tagsTextField.backgroundColor = Theme.muted
        tagsTextField.textColor = Theme.foreground
        tagsTextField.attributedPlaceholder = NSAttributedString(
            string: "标签1, 标签2, 标签3",
            attributes: [.foregroundColor: Theme.secondaryText]
        )

        contentView.addSubview(label)
        contentView.addSubview(tagsTextField)

        label.translatesAutoresizingMaskIntoConstraints = false
        tagsTextField.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: titleTextField.bottomAnchor, constant: 20),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            tagsTextField.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
            tagsTextField.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            tagsTextField.trailingAnchor.constraint(equalTo: label.trailingAnchor),
            tagsTextField.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func setupContentField() {
        let label = UILabel()
        label.text = "内容"
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = Theme.secondaryText

        contentTextView.font = .systemFont(ofSize: 16)
        contentTextView.backgroundColor = Theme.muted
        contentTextView.textColor = Theme.foreground
        contentTextView.layer.borderWidth = 1
        contentTextView.layer.borderColor = Theme.border.cgColor
        contentTextView.layer.cornerRadius = 8
        contentTextView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)

        contentView.addSubview(label)
        contentView.addSubview(contentTextView)

        label.translatesAutoresizingMaskIntoConstraints = false
        contentTextView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: tagsTextField.bottomAnchor, constant: 20),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            contentTextView.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
            contentTextView.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            contentTextView.trailingAnchor.constraint(equalTo: label.trailingAnchor),
            contentTextView.heightAnchor.constraint(equalToConstant: 200)
        ])
    }

    private func setupAttachmentSection() {
        let label = UILabel()
        label.text = "附件图片"
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = Theme.secondaryText

        attachmentButton.setTitle("+ 添加图片", for: .normal)
        attachmentButton.setTitleColor(Theme.primary, for: .normal)
        attachmentButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        attachmentButton.addTarget(self, action: #selector(addAttachmentTapped), for: .touchUpInside)

        attachmentCollectionView.backgroundColor = .clear
        attachmentCollectionView.register(AttachmentCell.self, forCellWithReuseIdentifier: "AttachmentCell")
        attachmentCollectionView.dataSource = self
        attachmentCollectionView.delegate = self
        attachmentCollectionView.isHidden = true

        contentView.addSubview(label)
        contentView.addSubview(attachmentButton)
        contentView.addSubview(attachmentCollectionView)

        label.translatesAutoresizingMaskIntoConstraints = false
        attachmentButton.translatesAutoresizingMaskIntoConstraints = false
        attachmentCollectionView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentTextView.bottomAnchor, constant: 20),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),

            attachmentButton.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            attachmentButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            attachmentCollectionView.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
            attachmentCollectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            attachmentCollectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            attachmentCollectionView.heightAnchor.constraint(equalToConstant: 88)
        ])
    }

    private func setupPostButton() {
        postButton.setTitle("发布", for: .normal)
        postButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        postButton.backgroundColor = Theme.primary
        postButton.setTitleColor(.white, for: .normal)
        postButton.layer.cornerRadius = 8
        postButton.addTarget(self, action: #selector(postTapped), for: .touchUpInside)

        loadingIndicator.color = .white
        loadingIndicator.hidesWhenStopped = true

        contentView.addSubview(postButton)
        postButton.addSubview(loadingIndicator)

        postButton.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            postButton.topAnchor.constraint(equalTo: attachmentCollectionView.bottomAnchor, constant: 30),
            postButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            postButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            postButton.heightAnchor.constraint(equalToConstant: 50),
            postButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),

            loadingIndicator.centerXAnchor.constraint(equalTo: postButton.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: postButton.centerYAnchor)
        ])
    }

    // MARK: - Native load / submit

    private func loadForm() {
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let info = try await NetworkManager.shared.fetchNewThreadForm(fid: self.fid)
                await MainActor.run { self.formInfo = info }
            } catch {
                await MainActor.run {
                    self.showAlert(title: "提示", message: "加载发帖表单失败：\(error.localizedDescription)")
                }
            }
        }
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func typeidButtonTapped() {
        let alert = UIAlertController(title: "选择分类", message: nil, preferredStyle: .actionSheet)
        for option in typeidOptions {
            alert.addAction(UIAlertAction(title: option.name, style: .default) { [weak self] _ in
                self?.typeid = option.id
                self?.typeidButton.setTitle(option.name, for: .normal)
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = typeidButton
            popover.sourceRect = typeidButton.bounds
        }
        present(alert, animated: true)
    }

    @objc private func addAttachmentTapped() {
        var config = PHPickerConfiguration()
        config.selectionLimit = max(1, 5 - selectedImages.count)
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func postTapped() {
        guard !isSubmitting else { return }

        guard let title = titleTextField.text, !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            showAlert(title: "错误", message: "请输入帖子标题")
            return
        }
        guard let content = contentTextView.text, !content.trimmingCharacters(in: .whitespaces).isEmpty else {
            showAlert(title: "错误", message: "请输入帖子内容")
            return
        }
        guard let info = formInfo else {
            showAlert(title: "提示", message: "正在加载表单数据，请稍后再试")
            loadForm()
            return
        }

        setSubmitting(true)
        let tags = tagsTextField.text ?? ""

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let aids = try await self.uploadSelectedImages(info: info)
                let ok = try await NetworkManager.shared.createThread(
                    fid: info.fid > 0 ? info.fid : self.fid,
                    title: title,
                    message: content,
                    typeid: self.typeid,
                    tags: tags,
                    formhash: info.formhash,
                    posttime: info.posttime,
                    attachAids: aids
                )
                await MainActor.run {
                    self.setSubmitting(false)
                    if ok {
                        self.delegate?.newThreadViewControllerDidPost(self)
                        self.dismiss(animated: true)
                    } else {
                        self.showAlert(title: "失败", message: "发布失败")
                    }
                }
            } catch {
                await MainActor.run {
                    self.setSubmitting(false)
                    self.showAlert(title: "错误", message: error.localizedDescription)
                }
            }
        }
    }

    private func uploadSelectedImages(info: NetworkManager.PostFormInfo) async throws -> [String] {
        guard !selectedImages.isEmpty else { return [] }
        guard let uploadHash = info.uploadHash else {
            throw NetworkError.postFailed("当前板块不支持上传附件")
        }
        let uid = LoginManager.shared.uid
        guard uid > 0 else { throw NetworkError.postFailed("登录状态异常，无法上传图片") }

        let referer = "https://www.4d4y.com/forum/post.php?action=newthread&fid=\(fid)"
        var aids: [String] = []
        for image in selectedImages {
            guard let data = image.jpegData(compressionQuality: 0.8) else { continue }
            let aid = try await NetworkManager.shared.uploadAttachment(
                imageData: data, uid: uid, uploadHash: uploadHash, referer: referer
            )
            aids.append(aid)
        }
        return aids
    }

    private func setSubmitting(_ submitting: Bool) {
        isSubmitting = submitting
        postButton.setTitle(submitting ? "" : "发布", for: .normal)
        postButton.isEnabled = !submitting
        if submitting { loadingIndicator.startAnimating() } else { loadingIndicator.stopAnimating() }
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - PHPickerViewControllerDelegate

extension NewThreadViewController: PHPickerViewControllerDelegate {

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        for result in results {
            result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                guard let image = object as? UIImage else { return }
                DispatchQueue.main.async {
                    guard let self = self, self.selectedImages.count < 5 else { return }
                    self.selectedImages.append(image)
                    self.updateAttachmentUI()
                }
            }
        }
    }

    private func updateAttachmentUI() {
        attachmentCollectionView.isHidden = selectedImages.isEmpty
        attachmentCollectionView.reloadData()
        let full = selectedImages.count >= 5
        attachmentButton.isEnabled = !full
        attachmentButton.setTitle(full ? "已达上限" : "+ 添加图片", for: .normal)
    }
}

// MARK: - UICollectionViewDataSource & Delegate

extension NewThreadViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return selectedImages.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "AttachmentCell", for: indexPath) as! AttachmentCell
        cell.configure(with: selectedImages[indexPath.item])
        cell.onDelete = { [weak self] in
            guard let self = self, indexPath.item < self.selectedImages.count else { return }
            self.selectedImages.remove(at: indexPath.item)
            self.updateAttachmentUI()
        }
        return cell
    }
}

// MARK: - AttachmentCell

class AttachmentCell: UICollectionViewCell {

    var onDelete: (() -> Void)?

    private let imageView = UIImageView()
    private let deleteButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        contentView.addSubview(imageView)

        deleteButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        deleteButton.tintColor = .white
        deleteButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        deleteButton.layer.cornerRadius = 12
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        contentView.addSubview(deleteButton)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            deleteButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            deleteButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            deleteButton.widthAnchor.constraint(equalToConstant: 24),
            deleteButton.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with image: UIImage) {
        imageView.image = image
    }

    @objc private func deleteTapped() {
        onDelete?()
    }
}
