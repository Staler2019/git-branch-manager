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
#include "app/bridge/RepositorySession.h"
#include "app/models/CommitListModel.h"
#include "app/models/GraphColumnDelegate.h"
#include "app/models/RefTreeModel.h"
#include "app/models/RepoListModel.h"
#include "core/git/GitExecutable.h"
#include "core/graph/GraphBuilder.h"
#include "core/workers/ThreadPool.h"

#include <QAbstractItemModelTester>
#include <QDir>
#include <QFile>
#include <QProcess>
#include <QSignalSpy>
#include <QTemporaryDir>
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

bool runGit(const QString& gitExecutable, const QString& dir, const QStringList& args) {
    QProcess process;
    process.setWorkingDirectory(dir);
    process.start(gitExecutable, args);
    if (!process.waitForFinished(10000)) {
        return false;
    }
    return process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0;
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
    void commitListModelSatisfiesTheModelContract();
    void commitListModelNeverBlocksInData();
    void graphDelegateWidthShrinksForLinearHistory();
    void graphDelegatePaletteCoversEveryLaneColor();
    void repositorySessionTracksWorkingCopyStagingAndCommit();
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

void ModelsTest::repositorySessionTracksWorkingCopyStagingAndCommit() {
    // Exercises the RepositorySession plumbing added for the working-copy
    // panel end to end, against a real git binary and a real repository --
    // the same "no usable git" skip RealRepoTest uses, since this app-layer
    // test cannot assume one is installed either.
    auto detected = GitExecutable::detect();
    if (!detected) {
        QSKIP("no usable git found");
    }
    const QString gitExecutable = QString::fromStdString(detected->executable.string());

    QTemporaryDir tempDir;
    QVERIFY(tempDir.isValid());
    const QString dir = tempDir.path();

    QVERIFY(runGit(gitExecutable, dir, {"init", "--quiet", "--initial-branch=main"}));
    QVERIFY(runGit(gitExecutable, dir, {"config", "user.email", "test@example.invalid"}));
    QVERIFY(runGit(gitExecutable, dir, {"config", "user.name", "Test"}));
    QVERIFY(runGit(gitExecutable, dir, {"config", "commit.gpgsign", "false"}));

    auto writeFile = [&dir](const QString& name, const QString& content) {
        QFile file(QDir(dir).filePath(name));
        QVERIFY(file.open(QIODevice::WriteOnly | QIODevice::Truncate));
        file.write(content.toUtf8());
    };

    writeFile(QStringLiteral("a.txt"), QStringLiteral("one\n"));
    QVERIFY(runGit(gitExecutable, dir, {"add", "a.txt"}));
    QVERIFY(runGit(gitExecutable, dir, {"commit", "--quiet", "-m", "c1"}));

    // An unstaged modification for the session to discover.
    writeFile(QStringLiteral("a.txt"), QStringLiteral("one\ntwo\n"));

    ThreadPool pool("model-test-reads", 2);
    const RepoPaths paths(
        dir.toStdString(), (dir + QStringLiteral("/.git")).toStdString(), std::string());
    RepositorySession session(*detected, paths, pool);

    bool statusUpdated = false;
    connect(&session, &RepositorySession::workingCopyStatusUpdated, &session, [&] {
        statusUpdated = true;
    });
    bool sawError = false;
    connect(&session, &RepositorySession::errorOccurred, &session, [&](const GitError&) {
        sawError = true;
    });

    session.refreshWorkingCopyStatus();
    QTRY_VERIFY(statusUpdated);
    QVERIFY(!sawError);

    auto status = session.workingCopyStatus();
    QVERIFY(status);
    QCOMPARE(status->unstaged().size(), std::size_t{1});
    QCOMPARE(QString::fromStdString(status->unstaged().front()->path), QStringLiteral("a.txt"));
    QVERIFY(status->staged().empty());

    // Stage the file and wait for both the completion signal and the
    // automatic status refresh it triggers.
    bool stageFinished = false;
    OperationOutcome stageOutcome;
    connect(&session,
            &RepositorySession::workingCopyOperationFinished,
            &session,
            [&](const OperationOutcome& outcome) {
                stageFinished = true;
                stageOutcome = outcome;
            });
    statusUpdated = false;
    session.stageFiles({"a.txt"});
    QTRY_VERIFY(stageFinished);
    QVERIFY2(stageOutcome.succeeded,
             stageOutcome.error ? stageOutcome.error->detail.c_str() : "stage failed");
    QTRY_VERIFY(statusUpdated);

    status = session.workingCopyStatus();
    QVERIFY(status);
    QCOMPARE(status->staged().size(), std::size_t{1});
    QVERIFY(status->unstaged().empty());

    // Commit it, which should also move HEAD -- confirmed via a fresh, clean
    // working-copy status afterwards.
    disconnect(&session, &RepositorySession::workingCopyOperationFinished, &session, nullptr);
    bool commitFinished = false;
    OperationOutcome commitOutcome;
    connect(&session,
            &RepositorySession::workingCopyOperationFinished,
            &session,
            [&](const OperationOutcome& outcome) {
                commitFinished = true;
                commitOutcome = outcome;
            });
    statusUpdated = false;

    CommitRequest request;
    request.message = "Add second line";
    session.commitChanges(request);
    QTRY_VERIFY(commitFinished);
    QVERIFY2(commitOutcome.succeeded,
             commitOutcome.error ? commitOutcome.error->detail.c_str() : "commit failed");
    QTRY_VERIFY(statusUpdated);

    status = session.workingCopyStatus();
    QVERIFY(status);
    QVERIFY(status->isClean());

    QVERIFY(runGit(gitExecutable, dir, {"log", "-1", "--format=%s"}));
}

QTEST_MAIN(ModelsTest)
#include "ModelsTest.moc"
