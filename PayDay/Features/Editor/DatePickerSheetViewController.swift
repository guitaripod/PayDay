import UIKit
import PayDayKit

/// A small modal wrapping a graphical date picker that returns a `CalendarDate`.
final class DatePickerSheetViewController: UIViewController {
    private let onPick: (CalendarDate) -> Void
    private let picker = UIDatePicker()
    private let initialDate: CalendarDate
    private let minimumDate: CalendarDate?
    private let maximumDate: CalendarDate?

    init(
        title: String,
        date: CalendarDate,
        minimumDate: CalendarDate? = nil,
        maximumDate: CalendarDate? = nil,
        onPick: @escaping (CalendarDate) -> Void
    ) {
        self.onPick = onPick
        self.initialDate = date
        self.minimumDate = minimumDate
        self.maximumDate = maximumDate
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignSystem.Color.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.commit() })

        picker.datePickerMode = .date
        picker.preferredDatePickerStyle = .inline
        picker.minimumDate = minimumDate.flatMap(Self.date(from:))
        picker.maximumDate = maximumDate.flatMap(Self.date(from:))
        if let date = Self.date(from: initialDate) { picker.date = date }
        picker.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            picker.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            picker.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])
        if let sheet = sheetPresentationController { sheet.detents = [.medium()] }
    }

    private func commit() {
        onPick(CalendarDate(picker.date))
        dismiss(animated: true)
    }

    private static func date(from calendarDate: CalendarDate) -> Date? {
        var comps = DateComponents()
        comps.year = calendarDate.year
        comps.month = calendarDate.month
        comps.day = calendarDate.day
        return Calendar(identifier: .gregorian).date(from: comps)
    }
}
