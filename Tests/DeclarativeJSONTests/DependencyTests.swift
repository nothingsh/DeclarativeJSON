import Combine
import DeclarativeCombine
import DeclarativeUIKit
import UIKit
import XCTest
@testable import DeclarativeJSON

/// The package wiring: both dependencies resolve and work from this target,
/// and a collection view lays out in the test process, where there is no
/// UIApplication, so the list can be tested without an app host.
@MainActor
final class DependencyTests: XCTestCase {

    func testAStackFromDeclarativeUIKitAndABindingFromDeclarativeCombineWorkTogether() {
        let title = CurrentValueSubject<String, Never>("before")
        let label = UILabel().bind(\.text, to: title)
        let stack = VStack(spacing: 4) { label }

        title.send("after")

        XCTAssertEqual(label.text, "after")
        XCTAssertEqual(stack.arrangedSubviews.count, 1)
        XCTAssertEqual(stack.spacing, 4)
    }

    func testACompositionalListWithSelfSizingCellsLaysOutInTheTestProcess() {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(44))
        let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)])
        let layout = UICollectionViewCompositionalLayout(section: NSCollectionLayoutSection(group: group))
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 480), collectionViewLayout: layout
        )
        collectionView.register(FixedHeightCell.self, forCellWithReuseIdentifier: "cell")
        let dataSource = UICollectionViewDiffableDataSource<Int, Int>(collectionView: collectionView) {
            collectionView, indexPath, height in
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
            (cell as? FixedHeightCell)?.height.constant = CGFloat(height)
            return cell
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        snapshot.appendItems([60, 90])
        dataSource.apply(snapshot, animatingDifferences: false)

        collectionView.layoutIfNeeded()

        let first = collectionView.cellForItem(at: IndexPath(item: 0, section: 0))
        let second = collectionView.cellForItem(at: IndexPath(item: 1, section: 0))
        XCTAssertEqual(first?.frame.height, 60)
        XCTAssertEqual(second?.frame.height, 90)
        XCTAssertEqual(second?.frame.minY, 60)
    }
}

/// A cell whose content asks for a fixed height, so that self-sizing has
/// something to measure.
private final class FixedHeightCell: UICollectionViewCell {
    let height: NSLayoutConstraint

    override init(frame: CGRect) {
        let content = UIView()
        height = content.heightAnchor.constraint(equalToConstant: 44)
        super.init(frame: frame)
        content.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: contentView.topAnchor),
            content.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            height,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("FixedHeightCell is built in code")
    }
}
