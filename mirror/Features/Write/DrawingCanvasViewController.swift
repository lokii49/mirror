import UIKit
import PencilKit

final class DrawingCanvasViewController: UIViewController {
    var onInsertDrawing: ((UIImage) -> Void)?

    private let canvasView = PKCanvasView()
    private let toolPicker = PKToolPicker()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        navigationItem.title = "Drawing"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Insert",
            style: .done,
            target: self,
            action: #selector(insertTapped)
        )

        canvasView.translatesAutoresizingMaskIntoConstraints = false
        canvasView.backgroundColor = .secondarySystemBackground
        canvasView.drawingPolicy = .anyInput
        canvasView.alwaysBounceVertical = true
        canvasView.contentSize = CGSize(width: view.bounds.width, height: 1200)
        canvasView.tool = PKInkingTool(.pen, color: .label, width: 6)
        view.addSubview(canvasView)

        NSLayoutConstraint.activate([
            canvasView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            canvasView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            canvasView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            canvasView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        canvasView.becomeFirstResponder()
        toolPicker.addObserver(canvasView)
        toolPicker.setVisible(true, forFirstResponder: canvasView)
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func insertTapped() {
        let image = canvasView.drawing.image(
            from: canvasView.drawing.bounds.insetBy(dx: -12, dy: -12),
            scale: UIScreen.main.scale
        )
        onInsertDrawing?(image)
        dismiss(animated: true)
    }
}
