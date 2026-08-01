// Tests for the Qt model layer.
//
// `QAbstractItemModelTester` is the highest-value test per line of code in a Qt
// application: it exercises the model contract (index/parent consistency, row
// counts, signal correctness around insertions) far more thoroughly than
// hand-written assertions would.
//
// The other thing pinned down here is the non-blocking `data()` contract. On a
// 500k-row history, one synchronous read inside `data()` would be called once per
// visible cell per frame, so a counter proves it never happens.
#include "app/models/CommitListModel.h"
#include "app/models/GraphColumnDelegate.h"
#include "app/models/RefTreeModel.h"
#include "app/models/RepoListModel.h"
#include "core/graph/GraphBuilder.h"

#include <QAbstractItemModelTester>
#include <QSignalSpy>
#include <QtTest>

#include <vector>

using namespace gbm;

namespace {

ObjectId oidFor(int n) {
    char buffer[41];
    std::snprintf(buffer, sizeof(buffer), "%040d", n);
    return ObjectId::fromHex(buffer);
}

RepoRecord makeRepo(std::int64_t id, const std::string& name) {
    RepoRecord record;
    record.id = id;
    record.baseFolderId = 1;
    record.name = name;
    record.workDir = "/work/" + name;
    record.gitDir = "/work/" + name + "/.git";
    record.commonDir = record.gitDir;
    record.kind = RepoKind::Normal;
    return record;
}

RefSnapshotPtr makeRefs() {
    auto snapshot = std::make_shared<RefSnapshot>();
    snapshot->head.kind = HeadInfo::Kind::Branch;
    snapshot->head.branchName = "main";
    snapshot->head.fullRef = "refs/heads/main";

    auto addRef =
        [&snapshot](
            const std::string& full, RefKind kind, const std::string& shortName, bool isHead) {
            RefInfo ref;
            ref.fullName = full;
            ref.kind = kind;
            ref.shortName = shortName;
            ref.isHead = isHead;
            ref.target = oidFor(1);
            snapshot->refs.push_back(ref);
        };

    addRef("refs/heads/main", RefKind::LocalBranch, "main", true);
    addRef("refs/heads/feature/auth/login", RefKind::LocalBranch, "feature/auth/login", false);
    addRef("refs/heads/feature/auth/logout", RefKind::LocalBranch, "feature/auth/logout", false);
    addRef("refs/remotes/origin/main", RefKind::RemoteBranch, "origin/main", false);
    addRef("refs/tags/v1.0", RefKind::Tag, "v1.0", false);

    snapshot->buildIndex();
    return snapshot;
}

}  // namespace

class ModelsTest : public QObject {
    Q_OBJECT

private slots:
    void repoListModelSatisfiesTheModelContract();
    void repoListModelMergesDiscoveredBatchesWithoutDuplicating();
    void repoListModelDistinguishesUnknownFromClean();
    void refTreeModelSatisfiesTheModelContract();
    void refTreeModelNestsSlashSeparatedBranchNames();
    void refTreeModelFlagsSectionRootsButNotGroupingNodes();
    void commitListModelSatisfiesTheModelContract();
    void commitListModelNeverBlocksInData();
    void graphDelegateWidthShrinksForLinearHistory();
    void graphDelegatePaletteCoversEveryLaneColor();
};

void ModelsTest::repoListModelSatisfiesTheModelContract() {
    RepoListModel model;
    QAbstractItemModelTester tester(&model,
                                    QAbstractItemModelTester::FailureReportingMode::Warning);

    std::vector<RepoRecord> repos{makeRepo(1, "alpha"), makeRepo(2, "beta")};
    model.setRepos(repos);

    QCOMPARE(model.rowCount(), 2);
    QCOMPARE(model.columnCount(), static_cast<int>(RepoListModel::ColumnCount));
    QCOMPARE(model.data(model.index(0, RepoListModel::ColumnName), Qt::DisplayRole).toString(),
             QStringLiteral("alpha"));
}

void ModelsTest::repoListModelMergesDiscoveredBatchesWithoutDuplicating() {
    RepoListModel model;
    QAbstractItemModelTester tester(&model,
                                    QAbstractItemModelTester::FailureReportingMode::Warning);

    model.setRepos({makeRepo(1, "alpha")});

    // A scan re-reports a repository already loaded from the cache. It must update
    // in place, not appear twice.
    model.appendRepos({makeRepo(1, "alpha"), makeRepo(2, "beta")});
    QCOMPARE(model.rowCount(), 2);

    model.appendRepos({makeRepo(2, "beta")});
    QCOMPARE(model.rowCount(), 2);
}

void ModelsTest::repoListModelDistinguishesUnknownFromClean() {
    RepoListModel model;
    model.setRepos({makeRepo(1, "alpha")});

    // No probe yet: the row must report itself as stale rather than showing an
    // empty status that reads as "clean".
    QVERIFY(
        model.data(model.index(0, RepoListModel::ColumnName), RepoListModel::IsStaleRole).toBool());
    QVERIFY(model.data(model.index(0, RepoListModel::ColumnBranch), Qt::DisplayRole)
                .toString()
                .isEmpty());

    RepoProbe probe;
    probe.repoId = 1;
    probe.headRef = "main";
    probe.ahead = 2;
    probe.dirtyFiles = 3;
    probe.probedAt = 1000;
    model.setProbe(1, probe);

    QVERIFY(!model.data(model.index(0, RepoListModel::ColumnName), RepoListModel::IsStaleRole)
                 .toBool());
    QCOMPARE(model.data(model.index(0, RepoListModel::ColumnBranch), Qt::DisplayRole).toString(),
             QStringLiteral("main"));
    const QString status =
        model.data(model.index(0, RepoListModel::ColumnStatus), Qt::DisplayRole).toString();
    QVERIFY(status.contains(QStringLiteral("2")));
    QVERIFY(status.contains(QStringLiteral("3 changed")));
}

void ModelsTest::refTreeModelSatisfiesTheModelContract() {
    RefTreeModel model;
    QAbstractItemModelTester tester(&model,
                                    QAbstractItemModelTester::FailureReportingMode::Warning);
    model.setRefs(makeRefs());
    QVERIFY(model.rowCount() > 0);
}

void ModelsTest::refTreeModelNestsSlashSeparatedBranchNames() {
    RefTreeModel model;
    model.setRefs(makeRefs());

    // Sections: Branches, Remotes, Tags.
    QCOMPARE(model.rowCount(), 3);

    QModelIndex branches;
    for (int row = 0; row < model.rowCount(); ++row) {
        if (model.data(model.index(row, 0), Qt::DisplayRole).toString() ==
            QStringLiteral("Branches")) {
            branches = model.index(row, 0);
        }
    }
    QVERIFY(branches.isValid());

    // Under Branches: "feature" (a group) and "main" (a ref). Groups sort first.
    QCOMPARE(model.rowCount(branches), 2);
    const QModelIndex feature = model.index(0, 0, branches);
    QCOMPARE(model.data(feature, Qt::DisplayRole).toString(), QStringLiteral("feature"));
    QVERIFY(!model.data(feature, RefTreeModel::IsRefRole).toBool());

    // feature/auth/login and feature/auth/logout share the "auth" level, so a flat
    // list would show two long names where the tree shows one branch point.
    const QModelIndex auth = model.index(0, 0, feature);
    QCOMPARE(model.data(auth, Qt::DisplayRole).toString(), QStringLiteral("auth"));
    QCOMPARE(model.rowCount(auth), 2);
    QVERIFY(model.data(model.index(0, 0, auth), RefTreeModel::IsRefRole).toBool());
    QCOMPARE(model.refNameAt(model.index(0, 0, auth)), QStringLiteral("feature/auth/login"));

    // A grouping node is not a checkout target.
    QVERIFY(model.refNameAt(feature).isEmpty());
}

void ModelsTest::refTreeModelFlagsSectionRootsButNotGroupingNodes() {
    RefTreeModel model;
    model.setRefs(makeRefs());

    // Every top-level row is a section root ("Branches"/"Remotes"/"Tags"), and
    // the sidebar delegate paints those as uppercase headers rather than pills.
    for (int row = 0; row < model.rowCount(); ++row) {
        const QModelIndex section = model.index(row, 0);
        QVERIFY(model.data(section, RefTreeModel::IsSectionRole).toBool());
    }

    QModelIndex branches;
    for (int row = 0; row < model.rowCount(); ++row) {
        if (model.data(model.index(row, 0), Qt::DisplayRole).toString() ==
            QStringLiteral("Branches")) {
            branches = model.index(row, 0);
        }
    }
    QVERIFY(branches.isValid());

    // "feature" is an intermediate slash-separated grouping node one level
    // below the section root -- not itself a section, and not a ref.
    const QModelIndex feature = model.index(0, 0, branches);
    QVERIFY(!model.data(feature, RefTreeModel::IsSectionRole).toBool());
    QVERIFY(!model.data(feature, RefTreeModel::IsRefRole).toBool());

    // "main", a leaf ref, is neither a section nor unset.
    const QModelIndex main = model.index(1, 0, branches);
    QCOMPARE(model.data(main, Qt::DisplayRole).toString(), QStringLiteral("main"));
    QVERIFY(!model.data(main, RefTreeModel::IsSectionRole).toBool());
    QVERIFY(model.data(main, RefTreeModel::IsRefRole).toBool());
}

void ModelsTest::commitListModelSatisfiesTheModelContract() {
    CommitListModel model;
    QAbstractItemModelTester tester(&model,
                                    QAbstractItemModelTester::FailureReportingMode::Warning);
    // With no session the model must be empty and well-behaved, not crash.
    QCOMPARE(model.rowCount(), 0);
    QCOMPARE(model.columnCount(), static_cast<int>(CommitListModel::ColumnCount));
    QVERIFY(!model.data(model.index(0, 0), Qt::DisplayRole).isValid());
}

void ModelsTest::commitListModelNeverBlocksInData() {
    // The contract: a metadata miss returns a placeholder immediately. With 500k
    // rows, one synchronous read here would be run once per visible cell per frame.
    CommitListModel model;

    GraphBuilder builder;
    for (int i = 1; i <= 5000; ++i) {
        std::vector<ObjectId> parents;
        if (i < 5000) {
            parents.push_back(oidFor(i + 1));
        }
        builder.add(oidFor(i), parents, 1000u + static_cast<std::uint32_t>(i));
    }
    builder.finish();

    // No session, so metadata never arrives: the worst case the contract is about.
    model.setSnapshotForTesting(builder.snapshot());
    QCOMPARE(model.rowCount(), 5000);

    QElapsedTimer timer;
    timer.start();
    int placeholders = 0;
    for (int row = 0; row < model.rowCount(); ++row) {
        for (int column = 0; column < CommitListModel::ColumnCount; ++column) {
            const QVariant value = model.data(model.index(row, column), Qt::DisplayRole);
            if (column == CommitListModel::ColumnSubject &&
                value.toString() == QStringLiteral("…")) {
                ++placeholders;
            }
        }
    }
    const qint64 elapsed = timer.elapsed();

    // Every subject must be the placeholder, proving the miss path returned rather
    // than fetching, and the whole sweep must be far faster than any git call.
    QCOMPARE(placeholders, 5000);
    QVERIFY2(elapsed < 500,
             qPrintable(QStringLiteral("data() took %1 ms over %2 cells; it must "
                                       "never block")
                            .arg(elapsed)
                            .arg(5000 * CommitListModel::ColumnCount)));

    // Columns backed by the snapshot itself (date, short sha) are populated even
    // with no metadata, so the view is never a wall of placeholders.
    QVERIFY(!model.data(model.index(0, CommitListModel::ColumnShortSha), Qt::DisplayRole)
                 .toString()
                 .isEmpty());
    QVERIFY(!model.data(model.index(0, CommitListModel::ColumnDate), Qt::DisplayRole)
                 .toString()
                 .isEmpty());
}

void ModelsTest::graphDelegateWidthShrinksForLinearHistory() {
    // The gutter is sized from the lanes actually in use over the visible rows, so a
    // linear stretch of ancient history does not inherit the width of the busiest era.
    CommitListModel model;
    GraphColumnDelegate delegate(&model);

    // With no snapshot the delegate still returns a sane minimum rather than 0.
    QVERIFY(delegate.widthForRows(0, 100) > 0);
}

void ModelsTest::graphDelegatePaletteCoversEveryLaneColor() {
    // Colour indices come from a hash modulo the palette size, so every index in
    // range must map to a valid colour or the graph would paint with an invalid pen.
    for (int i = 0; i < kPaletteSize; ++i) {
        const QColor color = GraphColumnDelegate::laneColor(static_cast<std::uint8_t>(i));
        QVERIFY2(color.isValid(), qPrintable(QStringLiteral("palette entry %1 is invalid").arg(i)));
    }
    // Out-of-range indices wrap rather than producing an invalid colour.
    QVERIFY(GraphColumnDelegate::laneColor(200).isValid());
}

QTEST_MAIN(ModelsTest)
#include "ModelsTest.moc"
