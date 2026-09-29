import UIKit

/// 阅读设置：调整帖子正文的字体大小与行距，并提供实时预览。
class SettingsViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let contentView = UIView()

    // 预览
    private let previewCard = UIView()
    private let previewLabel = UILabel()

    // 字体大小
    private let fontSizeValueLabel = UILabel()
    private let fontSizeSlider = UISlider()

    // 行距
    private let lineSpacingValueLabel = UILabel()
    private let lineSpacingSlider = UISlider()

    private let previewText = """
    这是帖子正文的预览效果。
    调整下方的字体大小和行距，即可实时看到阅读时的显示效果。
    Sample preview text for font size and line spacing.
    """

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadCurrentValues()
        updatePreview()
    }

    private func setupUI() {
        title = "阅读设置"
        view.backgroundColor = Theme.background

        // 恢复默认按钮
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "恢复默认",
            style: .plain,
            target: self,
            action: #selector(resetTapped)
        )

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

        // 预览卡片
        previewCard.backgroundColor = Theme.card
        previewCard.layer.cornerRadius = 12
        previewCard.layer.borderColor = Theme.border.cgColor
        previewCard.layer.borderWidth = 1
        contentView.addSubview(previewCard)

        previewLabel.numberOfLines = 0
        previewLabel.textColor = Theme.bodyText
        previewCard.addSubview(previewLabel)

        // 字体大小行
        let fontSizeTitle = makeSectionTitle("字体大小")
        fontSizeValueLabel.font = .systemFont(ofSize: 14, weight: .medium)
        fontSizeValueLabel.textColor = Theme.primary
        fontSizeValueLabel.textAlignment = .right

        fontSizeSlider.minimumValue = Float(ReadingSettings.minFontSize)
        fontSizeSlider.maximumValue = Float(ReadingSettings.maxFontSize)
        fontSizeSlider.tintColor = Theme.primary
        fontSizeSlider.addTarget(self, action: #selector(fontSizeChanged), for: .valueChanged)

        // 行距行
        let lineSpacingTitle = makeSectionTitle("行距")
        lineSpacingValueLabel.font = .systemFont(ofSize: 14, weight: .medium)
        lineSpacingValueLabel.textColor = Theme.primary
        lineSpacingValueLabel.textAlignment = .right

        lineSpacingSlider.minimumValue = Float(ReadingSettings.minLineSpacing)
        lineSpacingSlider.maximumValue = Float(ReadingSettings.maxLineSpacing)
        lineSpacingSlider.tintColor = Theme.primary
        lineSpacingSlider.addTarget(self, action: #selector(lineSpacingChanged), for: .valueChanged)

        // 布局：把标题+数值放一排，滑杆放下一排
        let fontSizeHeader = makeHeaderRow(title: fontSizeTitle, value: fontSizeValueLabel)
        let lineSpacingHeader = makeHeaderRow(title: lineSpacingTitle, value: lineSpacingValueLabel)

        let stack = UIStackView(arrangedSubviews: [
            fontSizeHeader, fontSizeSlider,
            lineSpacingHeader, lineSpacingSlider
        ])
        stack.axis = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(24, after: fontSizeSlider)
        contentView.addSubview(stack)

        previewCard.translatesAutoresizingMaskIntoConstraints = false
        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            previewCard.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            previewCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            previewCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            previewLabel.topAnchor.constraint(equalTo: previewCard.topAnchor, constant: 16),
            previewLabel.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor, constant: 16),
            previewLabel.trailingAnchor.constraint(equalTo: previewCard.trailingAnchor, constant: -16),
            previewLabel.bottomAnchor.constraint(equalTo: previewCard.bottomAnchor, constant: -16),

            stack.topAnchor.constraint(equalTo: previewCard.bottomAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -30)
        ])
    }

    private func makeSectionTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = Theme.titleText
        return label
    }

    private func makeHeaderRow(title: UILabel, value: UILabel) -> UIView {
        let row = UIStackView(arrangedSubviews: [title, value])
        row.axis = .horizontal
        row.alignment = .center
        return row
    }

    private func loadCurrentValues() {
        fontSizeSlider.value = Float(ReadingSettings.shared.fontSize)
        lineSpacingSlider.value = Float(ReadingSettings.shared.lineSpacing)
        updateValueLabels()
    }

    private func updateValueLabels() {
        fontSizeValueLabel.text = "\(Int(ReadingSettings.shared.fontSize)) pt"
        lineSpacingValueLabel.text = "\(Int(ReadingSettings.shared.lineSpacing)) pt"
    }

    private func updatePreview() {
        var style = ContentFormatter.Style()
        style.font = .systemFont(ofSize: ReadingSettings.shared.fontSize)
        style.lineSpacing = ReadingSettings.shared.lineSpacing
        // 预览用自定义样式，务必关掉缓存，避免污染默认样式的缓存
        previewLabel.attributedText = ContentFormatter.format(previewText, style: style, useCache: false)
    }

    @objc private func fontSizeChanged() {
        // 取整，避免出现 15.37pt 这种值
        let rounded = CGFloat(fontSizeSlider.value.rounded())
        ReadingSettings.shared.fontSize = rounded
        fontSizeSlider.value = Float(rounded)
        updateValueLabels()
        updatePreview()
        ReadingSettings.shared.notifyChange()
    }

    @objc private func lineSpacingChanged() {
        let rounded = CGFloat(lineSpacingSlider.value.rounded())
        ReadingSettings.shared.lineSpacing = rounded
        lineSpacingSlider.value = Float(rounded)
        updateValueLabels()
        updatePreview()
        ReadingSettings.shared.notifyChange()
    }

    @objc private func resetTapped() {
        ReadingSettings.shared.reset()
        loadCurrentValues()
        updatePreview()
        ReadingSettings.shared.notifyChange()
    }
}
