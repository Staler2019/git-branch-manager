#pragma once

#include <QObject>
#include <QString>

#include <filesystem>

class QTimer;

namespace gbm {

/// The UI-thread half of the askpass handshake -- see core/git/AskpassHelper.h
/// for the child-process half. Polls a request directory for the prompt a
/// blocked `git` subprocess is waiting on, and writes back whatever the user
/// (via CredentialDialog) or a cancellation decides.
///
/// Polling rather than a filesystem watcher: the directory is on local disk and
/// the interval is short enough that a human typing a password never notices,
/// while a watcher would need per-platform backends for no real benefit here.
class AskpassWatcher : public QObject {
    Q_OBJECT

public:
    explicit AskpassWatcher(QObject* parent = nullptr);
    ~AskpassWatcher() override;

    /// Starts watching `dir` for a request. A no-op if `dir` is empty, which is
    /// what a command gets when AskpassHelper::wire was never called for it.
    void start(std::filesystem::path dir);

    /// Stops watching and removes the request directory. Safe to call whether
    /// or not a prompt is currently outstanding.
    void stop();

signals:
    /// A `git` subprocess is blocked waiting for an answer to `prompt`.
    void promptReceived(QString prompt);

public slots:
    /// Answers the outstanding prompt. Also re-arms the watcher for a possible
    /// follow-up prompt in the same operation (e.g. a password after a
    /// username), since git can ask more than once per invocation.
    void answer(const QString& secret);

    /// Dismisses the outstanding prompt; the blocked git subprocess fails
    /// cleanly, exactly as if no credential helper were configured at all.
    void cancel();

private slots:
    void poll();

private:
    std::filesystem::path dir_;
    QTimer* timer_ = nullptr;
    bool requestSeen_ = false;
};

}  // namespace gbm
