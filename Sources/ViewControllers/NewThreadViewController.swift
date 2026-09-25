import UIKit
import WebKit
import PhotosUI

protocol NewThreadViewControllerDelegate: AnyObject {
    func newThreadViewControllerDidPost(_ controller: NewThreadViewController)
}

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

    private var webView: WKWebView?
    private var formhash: String?
    private var posttime: Int?
    private var uploadHash: String?
    private var typeid: Int = 0
    private var isSubmitting = false

    private var selectedImages: [UIImage] = []
    private var uploadedAttachments: [String] = [] // attachment IDs

    // Dynamic typeid options fetched from page
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

        // Load typeid options from static data
        let options = ForumManager.shared.getTypeidOptions(for: fid)
        self.typeidOptions = options.map { (id: $0.id, name: $0.name) }
        print("[NewThread] Loaded \(self.typeidOptions.count) typeid options for fid=\(fid)")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadFormPage()
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

    private func loadFormPage() {
        print("[NewThread] ===== DEBUG: loadFormPage =====")
        print("[NewThread] fid: \(fid)")
        print("[NewThread] User is logged in: \(LoginManager.shared.isLoggedIn)")
        print("[NewThread] uid: \(LoginManager.shared.uid)")
        print("[NewThread] =================================")

        // Remove old webView if exists
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil

        // Create configuration that shares cookies with URLSession
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        // Use a WKWebsiteDataStore that shares with URLSession
        // This ensures cookies are shared between WKWebView and native URLSession
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = WebClientConfig.userAgent
        webView.navigationDelegate = self
        webView.isHidden = true
        self.webView = webView
        view.addSubview(webView)

        // First URL - without topicsubmit=yes (that only comes at submit time)
        let postURL = URL(string: "https://www.4d4y.com/forum/post.php?action=newthread&fid=\(fid)")!
        print("[NewThread] Loading URL: \(postURL)")

        var request = URLRequest(url: postURL)
        request.timeoutInterval = 30

        webView.load(request)

        print("[NewThread] WKWebView load request sent...")
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func typeidButtonTapped() {
        let alert = UIAlertController(title: "选择分类", message: nil, preferredStyle: .actionSheet)

        for option in typeidOptions {
            let action = UIAlertAction(title: option.name, style: .default) { [weak self] _ in
                self?.typeid = option.id
                self?.typeidButton.setTitle(option.name, for: .normal)
            }
            alert.addAction(action)
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
        config.selectionLimit = 5 - selectedImages.count
        config.filter = .images

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func postTapped() {
        print("[NewThread] ===== DEBUG: postTapped =====")
        print("[NewThread] isSubmitting: \(isSubmitting)")
        print("[NewThread] fid: \(fid)")
        print("[NewThread] title: \(titleTextField.text ?? "nil")")
        print("[NewThread] content length: \(contentTextView.text?.count ?? 0)")
        print("[NewThread] typeid: \(typeid)")
        print("[NewThread] tags: \(tagsTextField.text ?? "nil")")
        print("[NewThread] webView exists: \(webView != nil)")
        print("[NewThread] formhash: \(formhash ?? "nil")")
        print("[NewThread] posttime: \(posttime ?? 0)")
        print("[NewThread] uploadHash: \(uploadHash ?? "nil")")
        print("[NewThread] selectedImages count: \(selectedImages.count)")
        print("[NewThread] =============================")

        guard !isSubmitting else {
            print("[NewThread] Already submitting, ignoring")
            return
        }

        guard let title = titleTextField.text, !title.isEmpty else {
            print("[NewThread] ERROR: Empty title")
            showAlert(title: "错误", message: "请输入帖子标题")
            return
        }

        guard let content = contentTextView.text, !content.isEmpty else {
            print("[NewThread] ERROR: Empty content")
            showAlert(title: "错误", message: "请输入帖子内容")
            return
        }

        // If formhash is missing, try to extract it now
        if formhash == nil || posttime == nil {
            print("[NewThread] Form data not ready, extracting now...")
            if let webView = webView {
                extractFormDataNow(webView) { [weak self] success in
                    guard let self = self else { return }
                    if success {
                        // Retry posting after extraction
                        DispatchQueue.main.async {
                            self.postTapped()
                        }
                    } else {
                        self.showAlert(title: "错误", message: "无法获取表单数据，请稍后再试")
                    }
                }
                return
            }
        }

        guard let webView = webView, let formhash = formhash else {
            print("[NewThread] ERROR: webView or formhash not ready")
            print("[NewThread] webView: \(webView == nil ? "nil" : "exists")")
            print("[NewThread] formhash: \(formhash == nil ? "nil" : formhash!)")
            showAlert(title: "提示", message: "正在加载表单数据，请稍后再试")
            return
        }

        print("[NewThread] All checks passed, starting submission...")

        isSubmitting = true
        postButton.setTitle("", for: .normal)
        loadingIndicator.startAnimating()

        // If there are images, upload them first
        if !selectedImages.isEmpty {
            print("[NewThread] Starting upload + post flow")
            uploadAttachmentsAndPostViaWebView(title: title, content: content, formhash: formhash)
        } else {
            print("[NewThread] Starting post without images")
            submitViaWebView(title: title, content: content, formhash: formhash)
        }
    }

    /// Extract form data immediately and call completion when done
    private func extractFormDataNow(_ webView: WKWebView, completion: @escaping (Bool) -> Void) {
        print("[NewThread] [EXTRACT_NOW] Starting immediate extraction...")

        // First, wait for document ready state
        webView.evaluateJavaScript("document.readyState") { result, error in
            if let state = result as? String {
                print("[NewThread] [EXTRACT_NOW] Document state: \(state)")

                if state == "loading" || state == "interactive" {
                    // Wait for complete state
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        guard let self = self else { return }
                        self.extractFormDataNow(webView, completion: completion)
                    }
                    return
                }
            }

            // Proceed with extraction if document is ready
            self.doExtractFormDataNow(webView, completion: completion)
        }
    }

    private func doExtractFormDataNow(_ webView: WKWebView, completion: @escaping (Bool) -> Void) {
        // Use a more robust extraction with Promise-style approach
        let extractionJS = #"""
        (function() {
            return new Promise(function(resolve) {
                // Wait for DOM to be ready
                if (document.readyState === 'loading') {
                    document.addEventListener('DOMContentLoaded', function() {
                        setTimeout(function() { resolve(extractData()); }, 100);
                    });
                } else {
                    resolve(extractData());
                }

                function extractData() {
                    var result = {
                        formhash: null,
                        posttime: null,
                        uploadHash: null,
                        hasForm: false
                    };

                    // Extract formhash
                    var formhashInput = document.querySelector('input[name=formhash]');
                    if (formhashInput) {
                        result.formhash = formhashInput.value;
                    }

                    // Extract posttime
                    var posttimeInput = document.querySelector('input[name=posttime]');
                    if (posttimeInput) {
                        result.posttime = posttimeInput.value;
                    }

                    // Extract upload hash
                    var uploadHashInput = document.querySelector('#imgattachform input[name=hash]') ||
                                         document.querySelector('#attachform input[name=hash]') ||
                                         document.querySelector('input[name=hash]');
                    if (uploadHashInput) {
                        result.uploadHash = uploadHashInput.value;
                    }

                    // Check if form exists
                    result.hasForm = !!document.getElementById('postform');

                    return result;
                }
            });
        })();
        """#

        webView.evaluateJavaScript(extractionJS) { [weak self] result, error in
            guard let self = self else {
                completion(false)
                return
            }

            if let error = error {
                print("[NewThread] [EXTRACT_NOW] JS Error: \(error.localizedDescription)")
                completion(false)
                return
            }

            guard let resultDict = result as? [String: Any] else {
                print("[NewThread] [EXTRACT_NOW] Invalid result format")
                completion(false)
                return
            }

            print("[NewThread] [EXTRACT_NOW] Extraction result: \(resultDict)")

            var success = false

            if let formhash = resultDict["formhash"] as? String, !formhash.isEmpty {
                print("[NewThread] [EXTRACT_NOW] formhash: \(formhash)")
                self.formhash = formhash
                success = true
            }

            if let posttimeStr = resultDict["posttime"] as? String, let posttime = Int(posttimeStr) {
                print("[NewThread] [EXTRACT_NOW] posttime: \(posttime)")
                self.posttime = posttime
            }

            if let uploadHash = resultDict["uploadHash"] as? String, !uploadHash.isEmpty {
                print("[NewThread] [EXTRACT_NOW] uploadHash: \(uploadHash)")
                self.uploadHash = uploadHash
            }

            completion(success)
        }
    }

    private func submitViaWebView(title: String, content: String, formhash: String) {
        guard let webView = webView else {
            handleSubmitError("无法提交帖子")
            return
        }

        let tags = tagsTextField.text ?? ""
        let currentPosttime = self.posttime ?? Int(Date().timeIntervalSince1970)
        let typeidValue = typeid > 0 ? String(typeid) : "0"

        print("[NewThread] ===== DEBUG: Submit Info =====")
        print("[NewThread] fid: \(fid)")
        print("[NewThread] formhash: \(formhash)")
        print("[NewThread] title: \(title)")
        print("[NewThread] content length: \(content.count)")
        print("[NewThread] typeid: \(typeidValue)")
        print("[NewThread] tags: \(tags)")
        print("[NewThread] posttime: \(currentPosttime)")
        print("[NewThread] ==============================")

        // Use raw string for JavaScript to avoid escaping issues
        let js = #"""
        (function() {
            try {
                var form = document.getElementById('postform') || document.querySelector('form');
                if (!form) {
                    console.error('Form not found!');
                    return {success: false, error: 'no_form'};
                }

                console.log('Found form:', form.id || 'no-id');
                console.log('Form action:', form.action);

                // Set subject field
                var subjectField = document.getElementById('subject');
                if (subjectField) {
                    subjectField.value = '#(title.jsEscaped)';
                    console.log('Set subject:', subjectField.value);
                } else {
                    console.error('Subject field not found!');
                }

                // For WYSIWYG mode, we need to set the value in the editor
                // The textarea is hidden and the actual content is in the WYSIWYG editor
                var messageField = document.getElementById('e_textarea');
                if (messageField) {
                    // In WYSIWYG mode, set the textarea value which gets synced
                    messageField.value = '#(content.jsEscaped)';
                    console.log('Set e_textarea, length:', messageField.value.length);

                    // Also try to set the WYSIWYG content if using wysiwyg
                    if (typeof editor != 'undefined' && editor) {
                        editor.html('#(content.jsEscaped)');
                        console.log('Set WYSIWYG editor content');
                    }
                } else {
                    // Fallback to textarea with name="message"
                    var msgField = form.querySelector('textarea[name="message"]');
                    if (msgField) {
                        msgField.value = '#(content.jsEscaped)';
                        console.log('Set message textarea, length:', msgField.value.length);
                    } else {
                        console.error('Message field not found!');
                    }
                }

                // Set typeid
                var typeidField = document.getElementById('typeid');
                if (typeidField) {
                    typeidField.value = '#(typeidValue)';
                    console.log('Set typeid:', typeidField.value);
                }

                // Verify message content was set correctly
                var verifyMsg = document.getElementById('e_textarea')?.value || form.querySelector('textarea[name="message"]')?.value || '';
                console.log('VERIFY message content length:', verifyMsg.length, 'preview:', verifyMsg.substring(0, 30));

                // Set tags
                var tagsField = document.getElementById('tags');
                if (tagsField) {
                    tagsField.value = '#(tags.jsEscaped)';
                    console.log('Set tags');
                }

                // Explicitly set wysiwyg=1 hidden field if exists
                var wysiwygField = form.querySelector('input[name=wysiwyg]');
                if (wysiwygField) {
                    wysiwygField.value = '1';
                    console.log('Set wysiwyg=1');
                }

                // Explicitly set iconid= empty field if exists
                var iconidField = form.querySelector('input[name=iconid]');
                if (iconidField) {
                    iconidField.value = '';
                    console.log('Set iconid empty');
                }

                // Log ALL form values before submit (including hidden fields)
                var allFields = form.querySelectorAll('input, select, textarea');
                console.log('=== ALL FORM FIELDS ===');
                for (var i = 0; i < allFields.length; i++) {
                    var f = allFields[i];
                    console.log('Field:', f.name || '(no name)', 'type:', f.type || 'text', '=', f.value ? f.value.substring(0, 50) : 'empty');
                }
                console.log('=== END FORM FIELDS ===');

                console.log('Submitting form...');

                // Ensure form action includes topicsubmit=yes (required by Discuz)
                if (!form.action.includes('topicsubmit=yes')) {
                    console.log('Adding topicsubmit=yes to form action');
                    form.action = form.action + '&topicsubmit=yes';
                }
                console.log('Final form action:', form.action);

                // Try clicking the submit button instead of form.submit()
                var submitBtn = document.getElementById('postsubmit');
                if (submitBtn) {
                    console.log('Found submit button, clicking...');
                    submitBtn.click();
                } else {
                    console.log('Submit button not found, using form.submit()');
                    form.submit();
                }
                return {success: true, formAction: form.action};
            } catch(e) {
                console.error('JS Exception:', e.message, e.stack);
                return {success: false, error: e.message};
            }
        })();
        """#

        print("[NewThread] Executing JavaScript to set form values and submit...")

        // First, check if form exists
        webView.evaluateJavaScript("document.getElementById('postform') ? 'FORM_FOUND' : 'FORM_NOT_FOUND'") { [weak self] result, error in
            guard let self = self else { return }
            print("[NewThread] Form check: \(String(describing: result))")

            if let error = error {
                print("[NewThread] Form check JS ERROR: \(error.localizedDescription)")
            }

            // Now execute the actual submit JavaScript
            self.executeSubmitJS(webView, title: title, content: content, formhash: formhash, js: js)
        }
    }

    private func executeSubmitJS(_ webView: WKWebView, title: String, content: String, formhash: String, js: String) {
        webView.evaluateJavaScript(js) { [weak self] result, error in
            if let error = error {
                print("[NewThread] JS ERROR: \(error.localizedDescription)")
                self?.handleSubmitError("提交失败: \(error.localizedDescription)")
                return
            }

            print("[NewThread] JS Result: \(String(describing: result))")
            print("[NewThread] Form submitted, waiting for navigation...")

            // Also log the current URL
            print("[NewThread] Current URL: \(self?.webView?.url?.absoluteString ?? "nil")")
        }

        // Note: Don't use fixed delay - rely on WKNavigationDelegate callbacks
        // The didFinish and decidePolicyFor callbacks will handle success detection
    }

    private func uploadAttachmentsAndPostViaWebView(title: String, content: String, formhash: String) {
        // For simplicity, post without attachments first if upload hash not available
        guard let uploadHash = self.uploadHash else {
            showAlert(title: "提示", message: "无法上传附件，将以纯文本形式发帖")
            submitViaWebView(title: title, content: content, formhash: formhash)
            return
        }

        let group = DispatchGroup()
        var uploadedIds: [String] = []

        for (index, image) in selectedImages.enumerated() {
            group.enter()

            uploadImage(image, hash: uploadHash) { [weak self] result in
                switch result {
                case .success(let attachmentId):
                    uploadedIds.append(attachmentId)
                    print("[NewThread] Uploaded image \(index + 1): \(attachmentId)")
                case .failure(let error):
                    print("[NewThread] Failed to upload image \(index + 1): \(error)")
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }

            // Build content with attachments
            var fullContent = content
            for attachmentId in uploadedIds {
                fullContent += "\n[attachimg]\(attachmentId)[/attachimg]"
            }

            self.submitViaWebView(title: title, content: fullContent, formhash: formhash)
        }
    }

    private func uploadAttachmentsAndPost(title: String, content: String, formhash: String) {
        guard let uploadHash = self.uploadHash else {
            showAlert(title: "错误", message: "无法上传附件，请重试")
            isSubmitting = false
            loadingIndicator.stopAnimating()
            postButton.setTitle("发布", for: .normal)
            return
        }

        let group = DispatchGroup()
        var uploadedIds: [String] = []

        for (index, image) in selectedImages.enumerated() {
            group.enter()

            uploadImage(image, hash: uploadHash) { [weak self] result in
                switch result {
                case .success(let attachmentId):
                    uploadedIds.append(attachmentId)
                    print("[NewThread] Uploaded image \(index + 1): \(attachmentId)")
                case .failure(let error):
                    print("[NewThread] Failed to upload image \(index + 1): \(error)")
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }

            // Build content with attachments
            var fullContent = content

            // Insert attachment references at the end of content
            for attachmentId in uploadedIds {
                fullContent += "\n[attachimg]\(attachmentId)[/attachimg]"
            }

            self.submitViaWebView(title: title, content: fullContent, formhash: formhash)
        }
    }

    private func uploadImage(_ image: UIImage, hash: String, completion: @escaping (Result<String, Error>) -> Void) {
        print("[NewThread] ===== DEBUG: uploadImage =====")
        print("[NewThread] hash: \(hash)")
        print("[NewThread] fid: \(fid)")

        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            print("[NewThread] ERROR: Failed to convert image to JPEG data")
            completion(.failure(NSError(domain: "ImageError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to data"])))
            return
        }
        print("[NewThread] Image data size: \(imageData.count) bytes")

        guard let uid = LoginManager.shared.uid as Int?, uid > 0 else {
            print("[NewThread] ERROR: Not logged in or invalid uid: \(LoginManager.shared.uid)")
            completion(.failure(NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not logged in"])))
            return
        }
        print("[NewThread] uid: \(uid)")

        let urlString = "https://www.4d4y.com/forum/misc.php?action=swfupload&operation=upload&simple=1&type=image"
        print("[NewThread] URL: \(urlString)")

        guard let url = URL(string: urlString) else {
            print("[NewThread] ERROR: Invalid URL")
            completion(.failure(NSError(domain: "URLError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }

        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.4d4y.com/forum/post.php?action=newthread&fid=\(fid)", forHTTPHeaderField: "Referer")
        request.setValue(WebClientConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 60 // Longer timeout for upload

        var body = Data()

        // Add uid field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"uid\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(uid)\r\n".data(using: .utf8)!)

        // Add hash field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"hash\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(hash)\r\n".data(using: .utf8)!)

        // Add file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"Filedata\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        print("[NewThread] Starting upload request (body size: \(body.count) bytes)...")

        NetworkManager.shared.session.dataTask(with: request) { data, response, error in
            print("[NewThread] Upload request completed")

            if let error = error {
                let nsError = error as NSError
                if nsError.code == NSURLErrorTimedOut {
                    print("[NewThread] Upload ERROR: Timeout")
                    completion(.failure(NSError(domain: "UploadError", code: -1, userInfo: [NSLocalizedDescriptionKey: "上传超时，请检查网络"])))
                } else {
                    print("[NewThread] Upload ERROR: \(error.localizedDescription)")
                    completion(.failure(error))
                }
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                print("[NewThread] Upload HTTP Status: \(httpResponse.statusCode)")
                print("[NewThread] Upload Response URL: \(httpResponse.url?.absoluteString ?? "nil")")

                // Check for error status codes
                if httpResponse.statusCode != 200 {
                    completion(.failure(NSError(domain: "UploadError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "上传失败 (HTTP \(httpResponse.statusCode))"])))
                    return
                }
            }

            guard let data = data,
                  let responseText = String(data: data, encoding: .utf8) else {
                print("[NewThread] Upload ERROR: No data or invalid encoding")
                completion(.failure(NSError(domain: "ResponseError", code: -1, userInfo: [NSLocalizedDescriptionKey: "服务器响应无效"])))
                return
            }

            print("[NewThread] Upload response length: \(responseText.count)")
            print("[NewThread] Upload response: \(responseText)")

            // Parse attachment ID from response
            let trimmed = responseText.trimmingCharacters(in: .whitespacesAndNewlines)

            // Try multiple patterns to extract ID

            // Pattern 1: Direct numeric ID
            if trimmed.range(of: "^[0-9]+$", options: .regularExpression) != nil {
                print("[NewThread] Upload SUCCESS: Direct ID = \(trimmed)")
                completion(.success(trimmed))
                return
            }

            // Pattern 2: aid=123 or aid:123
            if let regex = try? NSRegularExpression(pattern: "aid[=:\\s]+([0-9]+)", options: []),
               let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)),
               let range = Range(match.range(at: 1), in: trimmed) {
                let id = String(trimmed[range])
                print("[NewThread] Upload SUCCESS: Extracted ID from aid = \(id)")
                completion(.success(id))
                return
            }

            // Pattern 3: attachmentid or attachment_id
            if let regex = try? NSRegularExpression(pattern: "attachment[_]?id[=:\\s]+([0-9]+)", options: [.caseInsensitive]),
               let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)),
               let range = Range(match.range(at: 1), in: trimmed) {
                let id = String(trimmed[range])
                print("[NewThread] Upload SUCCESS: Extracted ID from attachment = \(id)")
                completion(.success(id))
                return
            }

            // Check for error indicators
            if trimmed.lowercased().contains("error") || trimmed.contains("错误") || trimmed.contains("失败") {
                print("[NewThread] Upload ERROR: Error message in response")
                completion(.failure(NSError(domain: "UploadError", code: -1, userInfo: [NSLocalizedDescriptionKey: "上传失败: \(trimmed)"])))
                return
            }

            // If no clear pattern but response exists, try to use it as ID
            if !trimmed.isEmpty && trimmed.count < 50 {
                print("[NewThread] Upload UNCERTAIN: Using response as ID = \(trimmed)")
                completion(.success(trimmed))
            } else {
                print("[NewThread] Upload ERROR: Cannot parse attachment ID")
                completion(.failure(NSError(domain: "ParseError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法解析上传结果"])))
            }
        }.resume()
    }

    private func handleSubmitSuccess() {
        isSubmitting = false
        loadingIndicator.stopAnimating()
        delegate?.newThreadViewControllerDidPost(self)
        dismiss(animated: true)
    }

    private func checkSubmitResult() {
        guard let webView = webView else {
            print("[NewThread] ERROR: webView is nil")
            handleSubmitError("无法检查提交结果")
            return
        }

        let currentURL = webView.url?.absoluteString ?? "nil"
        print("[NewThread] ===== DEBUG: checkSubmitResult =====")
        print("[NewThread] Current URL: \(currentURL)")
        print("[NewThread] isSubmitting: \(isSubmitting)")

        // Success: Navigated to viewthread page
        if currentURL.contains("viewthread") && currentURL.contains("tid=") {
            print("[NewThread] SUCCESS: Navigated to thread view")
            handleSubmitSuccess()
            return
        }

        // Success: URL contains tid= but not post.php
        if currentURL.contains("tid=") && !currentURL.contains("post.php") {
            print("[NewThread] SUCCESS: URL contains tid, assuming success")
            handleSubmitSuccess()
            return
        }

        // Check for error messages on page
        webView.evaluateJavaScript("document.body.innerText") { [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                print("[NewThread] JS Error getting page text: \(error.localizedDescription)")
                self.handleSubmitError("无法检查提交结果")
                return
            }

            if let text = result as? String {
                let textPreview = String(text.prefix(500)).replacingOccurrences(of: "\n", with: " ")
                print("[NewThread] Page text (first 500): \(textPreview)")

                // Check for various success indicators
                let successIndicators = ["发帖成功", "发布成功", "succeed", "发布主题成功", "主题发布成功", "操作成功", "发帖完成"]
                for indicator in successIndicators {
                    if text.contains(indicator) {
                        print("[NewThread] SUCCESS: Found success indicator: \(indicator)")
                        self.handleSubmitSuccess()
                        return
                    }
                }

                // Check for error indicators
                let errorIndicators = [
                    "错误", "失败", "请登录", "登录后方可", "验证码",
                    "请输入", "不允许", "非法", "操作失败", "发表帖子",
                    "请勿", "重复发帖", "禁止", "受限"
                ]
                for indicator in errorIndicators {
                    if text.contains(indicator) {
                        print("[NewThread] ERROR: Found error indicator: \(indicator)")
                        self.handleSubmitError("发帖失败: \(indicator)")
                        return
                    }
                }
            }

            // Check URL again after JS evaluation
            let urlAfterCheck = self.webView?.url?.absoluteString ?? currentURL
            print("[NewThread] URL after JS check: \(urlAfterCheck)")

            // Final determination based on URL
            if urlAfterCheck.contains("viewthread") {
                print("[NewThread] SUCCESS: URL changed to viewthread")
                self.handleSubmitSuccess()
            } else if urlAfterCheck.contains("topicsubmit=yes") || urlAfterCheck.contains("action=newthread") {
                // Still on post page - submission might have failed
                print("[NewThread] ERROR: Still on newthread page after submission")
                self.handleSubmitError("发帖可能失败，请手动检查")
            } else if urlAfterCheck != currentURL {
                // URL changed to something else - assume success
                print("[NewThread] URL changed to: \(urlAfterCheck)")
                self.handleSubmitSuccess()
            } else {
                print("[NewThread] WARNING: Could not determine result, assuming success")
                // Changed from error to success assumption - better UX
                self.handleSubmitSuccess()
            }
        }
    }

    private func handleSubmitError(_ message: String) {
        isSubmitting = false
        loadingIndicator.stopAnimating()
        postButton.setTitle("发布", for: .normal)
        showAlert(title: "错误", message: message)
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - WKNavigationDelegate

extension NewThreadViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let urlString = webView.url?.absoluteString ?? ""
        let expectedURL = "https://www.4d4y.com/forum/post.php?action=newthread&fid=\(fid)"

        print("[NewThread] ===== DEBUG: didFinish =====")
        print("[NewThread] URL: \(urlString)")
        print("[NewThread] Expected URL: \(expectedURL)")
        print("[NewThread] isSubmitting: \(isSubmitting)")
        print("[NewThread] =============================")

        // If we're in submitting state and navigated to viewthread, it's success
        if isSubmitting {
            if urlString.contains("viewthread") && urlString.contains("tid=") {
                print("[NewThread] SUCCESS: Thread view loaded")
                handleSubmitSuccess()
                return
            }

            // Check if still on post page - might be error
            if urlString.contains("post.php") {
                // Use a shorter delay to check result
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    self?.checkSubmitResult()
                }
                return
            }

            // If navigated elsewhere, check page content
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.checkSubmitResult()
            }
            return
        }

        // Normal page load - extract form data
        // Check URL - topicsubmit=yes in URL means something is wrong
        if urlString.contains("topicsubmit=yes") {
            print("[NewThread] [WARNING] URL contains topicsubmit=yes - possible redirect!")
        }

        // Check if URL is correct
        if !urlString.contains("action=newthread") || !urlString.contains("fid=\(fid)") {
            print("[NewThread] [WARNING] URL does not match expected pattern for newthread!")
        }

        // Extract immediately without delay
        extractFormData(webView)

        // Also wait for JS to finish loading and try again with longer delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            print("[NewThread] [RETRY] Extracting form data after 2s delay...")
            self?.extractFormData(webView)
        }
    }

    private func extractFormData(_ webView: WKWebView) {
        print("[NewThread] [EXTRACT] Starting form data extraction...")

        // First, check page title and body text
        webView.evaluateJavaScript("document.title + ' | ' + document.body.innerText.substring(0, 200)") { result, error in
            if let info = result as? String {
                print("[NewThread] [PAGE] Title+Text: \(info)")
            }
        }

        // Check if Cloudflare challenge
        webView.evaluateJavaScript("(document.body.innerHTML.includes('cloudflare') || document.body.innerHTML.includes('Checking your browser') || document.getElementById('challenge-body')) ? 'CLOUDFLARE' : 'OK'") { result, error in
            if let status = result as? String, status == "CLOUDFLARE" {
                print("[NewThread] [WARNING] Cloudflare challenge detected!")
            }
        }

        // Check if form exists
        webView.evaluateJavaScript("""
        (function() {
            var form = document.getElementById('postform');
            if (!form) {
                var forms = document.querySelectorAll('form');
                console.log('Forms found: ' + forms.length);
                forms.forEach(function(f, i) {
                    console.log('Form ' + i + ': id=' + f.id + ', action=' + f.action);
                });
                return 'NO_FORM';
            }
            return 'FORM_EXISTS';
        })();
        """) { result, error in
            print("[NewThread] [FORM_CHECK] \(String(describing: result))")
            if let error = error {
                print("[NewThread] [FORM_CHECK] Error: \(error)")
            }
        }

        // Extract formhash
        webView.evaluateJavaScript("document.querySelector('input[name=formhash]')?.value") { [weak self] result, error in
            guard let self = self else { return }

            if let hash = result as? String, !hash.isEmpty {
                print("[NewThread] [FORMHASH] Found via JS: \(hash)")
                self.formhash = hash
            } else {
                print("[NewThread] [FORMHASH] Not found via JS, trying HTML parsing...")
                webView.evaluateJavaScript("document.body.innerHTML") { [weak self] htmlResult, _ in
                    guard let html = htmlResult as? String else { return }

                    print("[NewThread] [FORMHASH] HTML length: \(html.count)")

                    if html.contains("formhash") {
                        print("[NewThread] [FORMHASH] HTML contains 'formhash'")
                        if let range = html.range(of: "formhash\" value=\"") {
                            let startIndex = range.upperBound
                            let endIndex = html.index(startIndex, offsetBy: 20, limitedBy: html.endIndex) ?? html.endIndex
                            let substring = String(html[startIndex..<endIndex])
                            if let hashEnd = substring.firstIndex(of: "\"") {
                                let hash = String(substring[..<hashEnd])
                                print("[NewThread] [FORMHASH] Extracted from HTML: \(hash)")
                                self?.formhash = hash
                            }
                        }
                    } else {
                        print("[NewThread] [FORMHASH] 'formhash' not found in HTML")
                    }

                    self?.logFormFields(webView)
                }
            }
        }

        // Extract posttime
        webView.evaluateJavaScript("document.querySelector('input[name=posttime]')?.value") { [weak self] result, error in
            if let time = result as? String, let posttime = Int(time) {
                print("[NewThread] [POSTTIME] Found: \(posttime)")
                self?.posttime = posttime
            } else {
                print("[NewThread] [POSTTIME] Not found")
            }
        }

        // Extract upload hash
        webView.evaluateJavaScript("(document.querySelector('#imgattachform input[name=hash]') || document.querySelector('#attachform input[name=hash]') || document.querySelector('input[name=hash]'))?.value") { [weak self] result, error in
            if let hash = result as? String, !hash.isEmpty {
                print("[NewThread] [UPLOAD_HASH] Found: \(hash)")
                self?.uploadHash = hash
            } else {
                print("[NewThread] [UPLOAD_HASH] Not found")
            }
        }

        // Extract typeid options from select element - try multiple methods
        webView.evaluateJavaScript(#"""
        (function() {
            console.log('[TYPEID] Starting extraction...');

            // Try to find the float_typeid div first (user's HTML shows this structure)
            var floatDiv = document.querySelector('.float_typeid');
            var typeidSelect = null;

            if (floatDiv) {
                console.log('[TYPEID] Found .float_typeid div');
                typeidSelect = floatDiv.querySelector('select[name="typeid"]') || floatDiv.querySelector('select#typeid') || floatDiv.querySelector('select');
                if (typeidSelect) {
                    console.log('[TYPEID] Found select inside .float_typeid:', typeidSelect.name, typeidSelect.id);
                }
            }

            // Fallback to direct ID lookup
            if (!typeidSelect) {
                typeidSelect = document.getElementById('typeid');
                console.log('[TYPEID] Fallback to getElementById:', typeidSelect ? 'found' : 'NOT found');
            }

            // Fallback to querySelector
            if (!typeidSelect) {
                typeidSelect = document.querySelector('select[name="typeid"]');
                console.log('[TYPEID] Fallback to querySelector by name:', typeidSelect ? 'found' : 'NOT found');
            }

            if (!typeidSelect) {
                console.log('[TYPEID] NO SELECT FOUND');
                return 'NO_TYPEID';
            }

            console.log('[TYPEID] Select found. options.length =', typeidSelect.options.length);

            // Use innerHTML to extract options (more reliable than options collection)
            var innerHTML = typeidSelect.innerHTML;
            console.log('[TYPEID] innerHTML:', innerHTML.substring(0, 500));

            // Parse options from innerHTML
            var options = [];
            var optionRegex = /<option[^>]*value="([^"]*)"[^>]*>([^<]*)</gi;
            var match;
            while ((match = optionRegex.exec(innerHTML)) !== null) {
                var value = match[1];
                var text = match[2].trim();
                // Decode HTML entities
                text = text.replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>');
                options.push({value: value, text: text});
                console.log('[TYPEID] Parsed option:', value, '->', text);
            }

            console.log('[TYPEID] Total parsed options:', options.length);
            console.log('[TYPEID] Final JSON:', JSON.stringify(options));
            return JSON.stringify(options);
        })();
        """#) { [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                print("[NewThread] [TYPEID] JS Error: \(error.localizedDescription)")
            }

            print("[NewThread] [TYPEID] Raw result: \(String(describing: result))")

            if let json = result as? String, !json.isEmpty, json != "NO_TYPEID" {
                print("[NewThread] [TYPEID] Options JSON: \(json)")

                // Parse the JSON and update typeidOptions
                if let data = json.data(using: .utf8),
                   let options = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    var parsedOptions: [(id: Int, name: String)] = []
                    for opt in options {
                        if let valueStr = opt["value"] as? String,
                           let value = Int(valueStr),
                           let text = opt["text"] as? String, !text.isEmpty {
                            parsedOptions.append((id: value, name: text))
                        }
                    }
                    if !parsedOptions.isEmpty {
                        self.typeidOptions = parsedOptions
                        print("[NewThread] [TYPEID] Updated options count: \(parsedOptions.count)")
                        print("[NewThread] [TYPEID] Options: \(parsedOptions)")
                    }
                }
            } else {
                print("[NewThread] [TYPEID] Not found or empty result")

                // Try alternative: parse from HTML directly
                webView.evaluateJavaScript("document.getElementById('typeid')?.outerHTML || 'NOT_FOUND'") { result, error in
                    print("[NewThread] [TYPEID] Alternative HTML check: \(String(describing: result))")
                }
            }
        }
    }

    private func logFormFields(_ webView: WKWebView) {
        webView.evaluateJavaScript("""
        (function() {
            var form = document.getElementById('postform') || document.querySelector('form');
            if (!form) {
                console.log('No form found');
                return;
            }
            console.log('Form found, fields:');
            var fields = form.querySelectorAll('input, select, textarea');
            fields.forEach(function(f) {
                console.log(' - ' + f.name + ' (type=' + f.type + ', id=' + f.id + ', value=' + (f.value ? f.value.substring(0, 50) : 'empty') + ')');
            });

            // Log typeid select specifically
            var typeidSelect = document.getElementById('typeid');
            console.log('Typeid select exists:', typeidSelect !== null);
            if (typeidSelect) {
                console.log('Typeid select options count:', typeidSelect.options.length);
                for (var i = 0; i < typeidSelect.options.length; i++) {
                    console.log('  [' + i + '] value=' + typeidSelect.options[i].value + ', text=' + typeidSelect.options[i].text);
                }
                console.log('Typeid select innerHTML:', typeidSelect.innerHTML.substring(0, 300));
            } else {
                console.log('Typeid select NOT FOUND in DOM');
            }
        })();
        """) { result, error in
            if let error = error {
                print("[NewThread] Error logging form fields: \(error)")
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[NewThread] ===== DEBUG: didFail =====")
        print("[NewThread] Error: \(error.localizedDescription)")
        print("[NewThread] isSubmitting: \(isSubmitting)")
        print("[NewThread] ==========================")

        if !isSubmitting {
            loadingIndicator.stopAnimating()
            postButton.setTitle("发布", for: .normal)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let url = webView.url?.absoluteString {
            print("[NewThread] [POLICY] Navigating to: \(url)")

            // If we're submitting and navigation goes to viewthread, allow it
            if isSubmitting && url.contains("viewthread") {
                print("[NewThread] [POLICY] Allowing navigation to thread view")
            }
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        let url = webView.url?.absoluteString ?? "nil"
        print("[NewThread] ===== DEBUG: didCommit =====")
        print("[NewThread] URL: \(url)")
        print("[NewThread] isSubmitting: \(isSubmitting)")
        print("[NewThread] =============================")

        if isSubmitting {
            if url.contains("viewthread") && url.contains("tid=") {
                print("[NewThread] SUCCESS: Navigated to thread view!")
                // Don't call handleSubmitSuccess directly here - let didFinish handle it
            } else if url.contains("post.php") && url.contains("topicsubmit=yes") {
                print("[NewThread] Submission in progress...")
            } else if url.contains("post.php") {
                print("[NewThread] Still on post page...")
            } else {
                print("[NewThread] Navigated to: \(url)")
            }
        }
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        print("[NewThread] [AUTH] Received authentication challenge")
        completionHandler(.performDefaultHandling, nil)
    }
}

// MARK: - PHPickerViewControllerDelegate

extension NewThreadViewController: PHPickerViewControllerDelegate {

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        for result in results {
            result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                if let image = object as? UIImage {
                    DispatchQueue.main.async {
                        self?.selectedImages.append(image)
                        self?.updateAttachmentUI()
                    }
                }
            }
        }
    }

    private func updateAttachmentUI() {
        attachmentCollectionView.isHidden = selectedImages.isEmpty
        attachmentCollectionView.reloadData()

        if selectedImages.count >= 5 {
            attachmentButton.isEnabled = false
            attachmentButton.setTitle("已达上限", for: .normal)
        }
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
            self?.selectedImages.remove(at: indexPath.item)
            self?.updateAttachmentUI()
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
