#pragma once

#include <QWidget>

#include <string>

class QLabel;
class QPlainTextEdit;
class QPushButton;

namespace gbm {

class RepositorySession;
struct WorkingCopyEntry;

/// The three-way (common ancestor / ours / theirs) conflict resolution view
/// for one conflicted path, wired to
/// RepositorySession::requestConflictSides/resolveConflict. Extracted from
/// WorkingCopyView::openConflictResolutionDialog so the same widget can be
/// reused outside a modal QDialog.
class ConflictResolvePanel : public QWidget {
    Q_OBJECT

public:
    explicit ConflictResolvePanel(QWidget* parent = nullptr);

    /// Loads `entry` and starts the background read of its three stages via
    /// `session`.
    void showEntry(RepositorySession* session, const WorkingCopyEntry& entry);

signals:
    /// A resolution (take ours / take theirs / mark resolved) has been
    /// submitted to the session.
    void resolutionSubmitted();
    /// The user cancelled without resolving.
    void cancelled();

private:
    void onConflictSidesReady(const QString& path,
                              const QString& ancestor,
                              const QString& ours,
                              const QString& theirs);
    void submitResolution(int choice);

    RepositorySession* session_ = nullptr;
    std::string path_;
    bool oursBlobMissing_ = false;
    bool theirsBlobMissing_ = false;

    QLabel* kindLabel_ = nullptr;
    QPlainTextEdit* ancestorEdit_ = nullptr;
    QPlainTextEdit* oursEdit_ = nullptr;
    QPlainTextEdit* theirsEdit_ = nullptr;
};

}  // namespace gbm
