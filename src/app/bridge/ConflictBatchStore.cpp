#include "app/bridge/ConflictBatchStore.h"

#include <QByteArray>
#include <QCryptographicHash>
#include <QSettings>
#include <QString>

namespace gbm {

namespace {

// commandDir() rather than workDir(): it falls back to gitDir() for a bare
// repository (workDir() is empty there -- see RepoPaths::isBare()), so this
// always has something non-empty to hash regardless of repo shape.
QString conflictBatchGroup(const RepoPaths& paths) {
    const QByteArray pathBytes = QByteArray::fromStdString(paths.commandDir().string());
    const QByteArray hash = QCryptographicHash::hash(pathBytes, QCryptographicHash::Sha256).toHex();
    return QStringLiteral("conflicts/%1").arg(QString::fromUtf8(hash));
}

}  // namespace

std::string ConflictBatchStore::operationFingerprint(const RepoPaths& paths,
                                                     const RepoState& state) {
    return paths.commandDir().string() + "|" + std::to_string(state.flags) + "|" +
           std::to_string(state.rebaseStep) + "/" + std::to_string(state.rebaseTotal);
}

ConflictBatch ConflictBatchStore::load(const RepoPaths& paths, const std::string& fingerprint) {
    QSettings settings;
    const QString group = conflictBatchGroup(paths);
    settings.beginGroup(group);

    const QString savedFingerprint = settings.value(QStringLiteral("fingerprint")).toString();
    if (savedFingerprint != QString::fromStdString(fingerprint)) {
        settings.endGroup();
        return ConflictBatch::forOperation(fingerprint);
    }

    std::vector<ConflictBatchEntry> entries;
    const int count = settings.beginReadArray(QStringLiteral("entries"));
    entries.reserve(static_cast<std::size_t>(count));
    for (int i = 0; i < count; ++i) {
        settings.setArrayIndex(i);
        ConflictBatchEntry entry;
        entry.path = settings.value(QStringLiteral("path")).toString().toStdString();
        entry.kind = static_cast<ConflictKind>(settings.value(QStringLiteral("kind")).toInt());
        entry.state =
            static_cast<ConflictFileState>(settings.value(QStringLiteral("state")).toInt());
        entries.push_back(std::move(entry));
    }
    settings.endArray();
    settings.endGroup();

    return ConflictBatch::restore(fingerprint, std::move(entries));
}

void ConflictBatchStore::save(const RepoPaths& paths, const ConflictBatch& batch) {
    QSettings settings;
    const QString group = conflictBatchGroup(paths);
    settings.beginGroup(group);

    settings.setValue(QStringLiteral("fingerprint"),
                      QString::fromStdString(batch.operationFingerprint()));

    const std::vector<ConflictBatchEntry>& entries = batch.entries();
    settings.beginWriteArray(QStringLiteral("entries"));
    for (std::size_t i = 0; i < entries.size(); ++i) {
        settings.setArrayIndex(static_cast<int>(i));
        settings.setValue(QStringLiteral("path"), QString::fromStdString(entries[i].path));
        settings.setValue(QStringLiteral("kind"), static_cast<int>(entries[i].kind));
        settings.setValue(QStringLiteral("state"), static_cast<int>(entries[i].state));
    }
    settings.endArray();
    settings.endGroup();
}

void ConflictBatchStore::clear(const RepoPaths& paths) {
    QSettings settings;
    settings.remove(conflictBatchGroup(paths));
}

}  // namespace gbm
