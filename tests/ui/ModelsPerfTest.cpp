// Timing check for CommitListModel::data()'s non-blocking contract.
//
// Split out of ModelsTest.cpp and given the "qt-perf" label (see
// tests/CMakeLists.txt), not "unit" or "perf": wall-clock assertions are too
// noisy on shared CI runners to gate every PR, so this runs nightly instead,
// on the same schedule as (but a separate job from) commit_graph_speedup_ratio
// -- see the "qt-models-perf" job in .github/workflows/perf-nightly.yml. It
// needs its own label and job because, unlike that Qt-free walk, this binary
// needs Qt: the "perf" label's only testPreset runs against the Qt-free
// core-only configurePreset, which never builds this target at all. The
// deterministic half of the contract -- a metadata miss returns the
// placeholder rather than fetching -- stays in
// ModelsTest::commitListModelDataMissReturnsPlaceholder, which needs no wall
// clock and does gate every PR.
#include "app/models/CommitListModel.h"
#include "core/graph/GraphBuilder.h"

#include <QtTest>

#include <vector>

using namespace gbm;

namespace {

ObjectId oidFor(int n) {
    char buffer[41];
    std::snprintf(buffer, sizeof(buffer), "%040d", n);
    return ObjectId::fromHex(buffer);
}

}  // namespace

class ModelsPerfTest : public QObject {
    Q_OBJECT

private slots:
    void commitListModelNeverBlocksInData();
};

void ModelsPerfTest::commitListModelNeverBlocksInData() {
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
    // Threshold has real headroom over observed CI noise: ~242ms locally,
    // 545-550ms on two independent CI runs (macOS job, different branches).
    // A synchronous git call in the miss path would blow past this by orders
    // of magnitude, not by a small multiple, so headroom here doesn't mask
    // the regression the test exists to catch.
    QCOMPARE(placeholders, 5000);
    QVERIFY2(elapsed < 1500,
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

QTEST_MAIN(ModelsPerfTest)
#include "ModelsPerfTest.moc"
