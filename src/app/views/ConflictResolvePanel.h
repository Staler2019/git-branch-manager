#pragma once

#include <QWidget>

#include <string>

class QLabel;
class QPlainTextEdit;
class QPushButton;

namespace gbm {

class RepositorySession;
struct WorkingCopyEntry;

/// One conflicted path's resolution view: left = the current branch's side
/// (ours), middle = the editable resolved content (the actual working-tree
/// file, conflict markers and all), right = the merged-in branch's side
/// (theirs). Wired to
/// RepositorySession::requestConflictSides/requestWorkingTreeContent/
/// resolveConflict. Extracted from
/// WorkingCopyView::openConflictResolutionDialog so the same widget can be
/// reused outside a modal QDialog.
class ConflictResolvePanel : public QWidget {
    Q_OBJECT

public:
    explicit ConflictResolvePanel(QWidget* parent = nullptr);

    /// Loads `entry` and starts the background reads of its three stages and
    /// its on-disk (editable) content via `session`.
    void showEntry(RepositorySession* session, const WorkingCopyEntry& entry);

signals:
    /// A resolution (take left / take right / save & mark resolved) has been
    /// submitted to the session.
    void resolutionSubmitted();
    /// The user cancelled without resolving.
    void cancelled();

private:
    void onConflictSidesReady(const QString& path,
                              const QString& ancestor,
                              const QString& ours,
                              const QString& theirs);
    void onWorkingTreeContentReady(const QString& path, const QString& content, bool editable);
    void submitResolution(int choice);

    RepositorySession* session_ = nullptr;
    std::string path_;
    bool oursBlobMissing_ = false;
    bool theirsBlobMissing_ = false;
    /// True when the middle column's on-disk content had CRLF line endings,
    /// so a save can restore them -- QPlainTextEdit normalises everything it
    /// displays to bare `\n`, so this has to be captured before the content
    /// ever reaches the widget.
    bool middleContentHasCrlf_ = false;
    /// Mirrors whether the middle column is currently editable (i.e. the
    /// on-disk content decoded as text) -- gates the Save button.
    bool middleEditable_ = false;

    QLabel* kindLabel_ = nullptr;
    QPlainTextEdit* oursEdit_ = nullptr;
    QPlainTextEdit* middleEdit_ = nullptr;
    QPlainTextEdit* theirsEdit_ = nullptr;
    QPushButton* saveButton_ = nullptr;
};

}  // namespace gbm
