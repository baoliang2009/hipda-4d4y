import UIKit
import PhotosUI

protocol ReplyViewControllerDelegate: AnyObject {
    func replyViewControllerDidPost(_ controller: ReplyViewController)
    func replyViewControllerDidCancel(_ controller: ReplyViewController)
}

/// 回复帖子。
///
/// 已从 WKWebView 方案改为原生：加载回复页表单、提交、上传附件全部走 URLSession。
/// 旧方案靠隐藏 WKWebView 打开 post.php 取 formhash 再 form.submit()，但 WKWebView
/// 会被 Cloudflare Turnstile 拦死（见 CLAUDE.md），formhash 取不到、回复根本发不出去，
/// 而且原来完全没有附件功能。现在两者都补上。
class ReplyViewController: UIViewController {

    weak var delegate: ReplyViewControllerDelegate?

    private let tid: Int
    private let reppost: Int?  // 被回复的楼层（仅用于标题展示）
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let headerLabel = UILabel()
    private let contentTextView = UITextView()
    private let attachmentButton = UIButton(type: .system)
    private let attachmentCollectionView: UICollectionView
    private let submitButton = UIButton(type: .system)
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    private var formInfo: NetworkManager.PostFormInfo?
    private var selectedImages: [UIImage] = []
    private var isSubmitting = false

    init(tid: Int) {
        self.tid = tid
        self.reppost = nil
        self.attachmentCollectionView = ReplyViewController.makeAttachmentCollectionView()
        super.init(nibName: nil, bundle: nil)
    }

    init(tid: Int, reppost: Int) {
        self.tid = tid
        self.reppost = reppost
        self.attachmentCollectionView = ReplyViewController.makeAttachmentCollectionView()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func makeAttachmentCollectionView() -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 80, height: 80)
        layout.minimumInteritemSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        return UICollectionView(frame: .zero, collectionViewLayout: layout)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadReplyForm()
    }

    private func setupUI() {
        title = "回复"
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

        setupHeaderLabel()
        setupContentField()
        setupAttachmentSection()
        setupSubmitButton()
    }

    private func setupHeaderLabel() {
        headerLabel.font = .systemFont(ofSize: 14, weight: .medium)
        headerLabel.textColor = Theme.secondaryText
        headerLabel.text = reppost != nil ? "回复 #\(reppost!) 楼" : "回复楼主"

        contentView.addSubview(headerLabel)
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            headerLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            headerLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20)
        ])
    }

    private func setupContentField() {
        let label = UILabel()
        label.text = "回复内容"
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
            label.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 16),
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

    private func setupSubmitButton() {
        submitButton.setTitle("提交回复", for: .normal)
        submitButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        submitButton.backgroundColor = Theme.primary
        submitButton.setTitleColor(.white, for: .normal)
        submitButton.layer.cornerRadius = 8
        submitButton.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)

        loadingIndicator.color = .white
        loadingIndicator.hidesWhenStopped = true

        contentView.addSubview(submitButton)
        submitButton.addSubview(loadingIndicator)

        submitButton.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            submitButton.topAnchor.constraint(equalTo: attachmentCollectionView.bottomAnchor, constant: 24),
            submitButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            submitButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            submitButton.heightAnchor.constraint(equalToConstant: 50),
            submitButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),

            loadingIndicator.centerXAnchor.constraint(equalTo: submitButton.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: submitButton.centerYAnchor)
        ])
    }

    private func loadReplyForm() {
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let info = try await NetworkManager.shared.fetchReplyForm(tid: self.tid)
                await MainActor.run { self.formInfo = info }
            } catch {
                await MainActor.run {
                    self.showAlert(title: "提示", message: "加载回复表单失败：\(error.localizedDescription)")
                }
            }
        }
    }

    @objc private func cancelTapped() {
        delegate?.replyViewControllerDidCancel(self)
        dismiss(animated: true)
    }

    @objc private func addAttachmentTapped() {
        var config = PHPickerConfiguration()
        config.selectionLimit = max(1, 5 - selectedImages.count)
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func submitTapped() {
        guard !isSubmitting else { return }

        let message = contentTextView.text ?? ""
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedImages.isEmpty else {
            showAlert(title: "错误", message: "请输入回复内容")
            return
        }
        guard let info = formInfo else {
            showAlert(title: "提示", message: "正在加载表单数据，请稍后再试")
            loadReplyForm()
            return
        }

        setSubmitting(true)

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let aids = try await self.uploadSelectedImages(info: info)
                let ok = try await NetworkManager.shared.replyThread(
                    tid: self.tid,
                    fid: info.fid,
                    message: message,
                    formhash: info.formhash,
                    posttime: info.posttime,
                    attachAids: aids
                )
                await MainActor.run {
                    self.setSubmitting(false)
                    if ok {
                        self.delegate?.replyViewControllerDidPost(self)
                        self.dismiss(animated: true)
                    } else {
                        self.showAlert(title: "失败", message: "回复发送失败")
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

    /// 逐张上传所选图片，返回附件 aid 列表。任一张失败即整体报错。
    private func uploadSelectedImages(info: NetworkManager.PostFormInfo) async throws -> [String] {
        guard !selectedImages.isEmpty else { return [] }
        guard let uploadHash = info.uploadHash else {
            throw NetworkError.postFailed("当前板块不支持上传附件")
        }
        let uid = LoginManager.shared.uid
        guard uid > 0 else { throw NetworkError.postFailed("登录状态异常，无法上传图片") }

        let referer = "https://www.4d4y.com/forum/post.php?action=reply&tid=\(tid)"
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
        submitButton.setTitle(submitting ? "" : "提交回复", for: .normal)
        submitButton.isEnabled = !submitting
        if submitting { loadingIndicator.startAnimating() } else { loadingIndicator.stopAnimating() }
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - PHPickerViewControllerDelegate

extension ReplyViewController: PHPickerViewControllerDelegate {
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

extension ReplyViewController: UICollectionViewDataSource, UICollectionViewDelegate {
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
