#pragma once

#include <QWidget>

#include <memory>

class QCheckBox;
class QLabel;
class QLineEdit;
class QSpinBox;

namespace gbm {

class RepositorySession;
struct LocalIdentity;

/// The Repository Settings tab: three per-repository cards (identity,
/// read-only summary, performance) plus a footer pointing at the app-wide
/// Preferences dialog.
///
/// Two of the three cards reach different depths, and this class is explicit
/// about which:
/// - "This repository" is a live, read-only view of `RepositorySession`.
/// - "Git identity for this repository" is fully wired: the override
///   checkbox and fields read and write real `git config --local` state
///   through `RepositorySession::setLocalIdentityOverride` /
///   `clearLocalIdentityOverride` -- see `ConfigOps.h`.
/// - "Performance for this repository" persists to `QSettings` (keyed by
///   repository path) and is read back by `RepositorySession::refreshHistory`
///   to cap `HistoryQuery::maxCount` on the next history walk -- see
///   `maxGraphRowsSetting`/`performanceSettingsKeyPrefix` in
///   RepositorySession.cpp, which must agree with `settingsKeyPrefix()`/
///   `kDefaultMaxGraphRows` below on the exact key format.
class RepositoryPage : public QWidget {
    Q_OBJECT

public:
    explicit RepositoryPage(QWidget* parent = nullptr);
    ~RepositoryPage() override;

    /// Attaches to a repository, or detaches (and clears everything) when
    /// `session` is null.
    void setSession(RepositorySession* session);

signals:
    /// The footer's "File -> Preferences" link was clicked. MainWindow owns
    /// opening PreferencesDialog -- this page has no dependency on it.
    void openPreferencesRequested();

private slots:
    void onLocalIdentityUpdated();
    void onOverrideToggled(bool checked);
    void onIdentityFieldEdited();

private:
    void buildUi();
    void refreshRepositoryCard();
    void applyIdentity(const LocalIdentity& identity);
    /// QSettings key prefix for this repository's Performance settings,
    /// derived from its command directory so it survives being reopened
    /// (renaming or moving the repo forfeits continuity -- an acceptable
    /// limit for a forward-compatible placeholder setting).
    QString settingsKeyPrefix() const;
    void loadPerformanceSettings();
    void savePerformanceSetting();

    RepositorySession* session_ = nullptr;

    QLabel* repoNameValue_ = nullptr;
    QLabel* defaultRemoteValue_ = nullptr;

    QCheckBox* identityOverrideCheck_ = nullptr;
    QLineEdit* identityNameEdit_ = nullptr;
    QLineEdit* identityEmailEdit_ = nullptr;
    /// Guards onIdentityFieldEdited/onOverrideToggled against firing while
    /// applyIdentity() is programmatically populating the fields from a
    /// fresh read -- without this, an incoming refresh would immediately
    /// re-submit itself as a write.
    bool applyingIdentity_ = false;

    QCheckBox* largeRepoModeCheck_ = nullptr;
    QSpinBox* maxGraphRowsSpin_ = nullptr;
    QCheckBox* autoFetchCheck_ = nullptr;

    QLabel* footerLabel_ = nullptr;
};

}  // namespace gbm
