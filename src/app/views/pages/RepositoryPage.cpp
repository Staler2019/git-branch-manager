#include "app/views/pages/RepositoryPage.h"

#include "app/bridge/RepositorySession.h"
#include "app/bridge/ThemeManager.h"
#include "core/git/ops/ConfigOps.h"
#include "core/git/ops/RemoteOps.h"

#include <QCheckBox>
#include <QFrame>
#include <QHBoxLayout>
#include <QLabel>
#include <QLineEdit>
#include <QSettings>
#include <QSpinBox>
#include <QVBoxLayout>

#include <algorithm>

namespace gbm {

namespace {

constexpr int kDefaultMaxGraphRows = 5000;

QFrame* buildCard(QWidget* parent, const QString& title) {
    auto* frame = new QFrame(parent);
    frame->setObjectName(QStringLiteral("gbmPanel"));
    auto* layout = new QVBoxLayout(frame);
    layout->setContentsMargins(16, 12, 16, 12);
    layout->setSpacing(8);

    auto* header = new QLabel(title, frame);
    header->setObjectName(QStringLiteral("gbmPanelHeader"));
    layout->addWidget(header);

    return frame;
}

}  // namespace

RepositoryPage::RepositoryPage(QWidget* parent) : QWidget(parent) {
    buildUi();
}

RepositoryPage::~RepositoryPage() = default;

void RepositoryPage::buildUi() {
    auto* outerLayout = new QVBoxLayout(this);
    outerLayout->setContentsMargins(16, 16, 16, 16);
    outerLayout->setSpacing(16);

    // --- "This repository" --------------------------------------------------
    QFrame* repoCard = buildCard(this, tr("This repository"));
    auto* repoCardLayout = qobject_cast<QVBoxLayout*>(repoCard->layout());
    auto* nameRow = new QHBoxLayout();
    nameRow->addWidget(new QLabel(tr("Name"), repoCard));
    repoNameValue_ = new QLabel(tr("(no repository open)"), repoCard);
    nameRow->addWidget(repoNameValue_, 1);
    repoCardLayout->addLayout(nameRow);

    auto* remoteRow = new QHBoxLayout();
    remoteRow->addWidget(new QLabel(tr("Default remote"), repoCard));
    defaultRemoteValue_ = new QLabel(tr("(none)"), repoCard);
    remoteRow->addWidget(defaultRemoteValue_, 1);
    repoCardLayout->addLayout(remoteRow);
    outerLayout->addWidget(repoCard);

    // --- "Git identity for this repository" ---------------------------------
    QFrame* identityCard = buildCard(this, tr("Git identity for this repository"));
    auto* identityCardLayout = qobject_cast<QVBoxLayout*>(identityCard->layout());

    identityOverrideCheck_ = new QCheckBox(
        tr("Override the global Git identity for this repository only"), identityCard);
    identityCardLayout->addWidget(identityOverrideCheck_);
    connect(identityOverrideCheck_, &QCheckBox::toggled, this, &RepositoryPage::onOverrideToggled);

    auto* nameFieldRow = new QHBoxLayout();
    nameFieldRow->addWidget(new QLabel(tr("Name"), identityCard));
    identityNameEdit_ = new QLineEdit(identityCard);
    identityNameEdit_->setEnabled(false);
    nameFieldRow->addWidget(identityNameEdit_, 1);
    identityCardLayout->addLayout(nameFieldRow);

    auto* emailFieldRow = new QHBoxLayout();
    emailFieldRow->addWidget(new QLabel(tr("Email"), identityCard));
    identityEmailEdit_ = new QLineEdit(identityCard);
    identityEmailEdit_->setEnabled(false);
    emailFieldRow->addWidget(identityEmailEdit_, 1);
    identityCardLayout->addLayout(emailFieldRow);

    connect(identityNameEdit_,
            &QLineEdit::editingFinished,
            this,
            &RepositoryPage::onIdentityFieldEdited);
    connect(identityEmailEdit_,
            &QLineEdit::editingFinished,
            this,
            &RepositoryPage::onIdentityFieldEdited);

    outerLayout->addWidget(identityCard);

    // --- "Performance for this repository" -----------------------------------
    QFrame* perfCard = buildCard(this, tr("Performance for this repository"));
    auto* perfCardLayout = qobject_cast<QVBoxLayout*>(perfCard->layout());

    largeRepoModeCheck_ = new QCheckBox(
        tr("Large-repository mode — paginate history instead of loading full graph"), perfCard);
    perfCardLayout->addWidget(largeRepoModeCheck_);
    connect(largeRepoModeCheck_, &QCheckBox::toggled, this, [this](bool checked) {
        maxGraphRowsSpin_->setEnabled(checked);
        savePerformanceSetting();
    });

    auto* rowsFieldRow = new QHBoxLayout();
    rowsFieldRow->addWidget(new QLabel(tr("Max graph rows per page"), perfCard));
    maxGraphRowsSpin_ = new QSpinBox(perfCard);
    maxGraphRowsSpin_->setRange(100, 1000000);
    maxGraphRowsSpin_->setSingleStep(500);
    maxGraphRowsSpin_->setValue(kDefaultMaxGraphRows);
    maxGraphRowsSpin_->setEnabled(false);
    rowsFieldRow->addWidget(maxGraphRowsSpin_, 1);
    perfCardLayout->addLayout(rowsFieldRow);
    connect(maxGraphRowsSpin_, qOverload<int>(&QSpinBox::valueChanged), this, [this](int) {
        savePerformanceSetting();
    });

    auto* captionLabel = new QLabel(
        tr("Every cap is visible — when the graph is capped, the history view says how many "
           "commits it left out. Applies the next time history is refreshed for this "
           "repository."),
        perfCard);
    captionLabel->setObjectName(QStringLiteral("gbmPanelCaption"));
    captionLabel->setWordWrap(true);
    perfCardLayout->addWidget(captionLabel);

    outerLayout->addWidget(perfCard);

    // --- "Sync" -------------------------------------------------------------
    QFrame* syncCard = buildCard(this, tr("Sync"));
    auto* syncCardLayout = qobject_cast<QVBoxLayout*>(syncCard->layout());

    autoFetchCheck_ =
        new QCheckBox(tr("Automatically fetch when opening this repository"), syncCard);
    syncCardLayout->addWidget(autoFetchCheck_);
    connect(autoFetchCheck_, &QCheckBox::toggled, this, [this](bool) { savePerformanceSetting(); });

    auto* syncCaptionLabel =
        new QLabel(tr("Runs quietly in the background. If it needs credentials that aren't "
                      "already stored, it simply fails without prompting -- fetch manually from "
                      "the toolbar if you need to sign in."),
                   syncCard);
    syncCaptionLabel->setObjectName(QStringLiteral("gbmPanelCaption"));
    syncCaptionLabel->setWordWrap(true);
    syncCardLayout->addWidget(syncCaptionLabel);

    outerLayout->addWidget(syncCard);

    // --- footer ----------------------------------------------------------------
    footerLabel_ = new QLabel(
        tr("App-wide preferences (theme, default clone directory, global Git identity) live "
           "under <a href=\"#preferences\">File → Preferences</a>."),
        this);
    footerLabel_->setObjectName(QStringLiteral("gbmPanelCaption"));
    footerLabel_->setWordWrap(true);
    footerLabel_->setTextFormat(Qt::RichText);
    footerLabel_->setTextInteractionFlags(Qt::TextBrowserInteraction);
    footerLabel_->setOpenExternalLinks(false);
    connect(footerLabel_, &QLabel::linkActivated, this, [this](const QString&) {
        emit openPreferencesRequested();
    });
    outerLayout->addWidget(footerLabel_);

    outerLayout->addStretch(1);
}

void RepositoryPage::setSession(RepositorySession* session) {
    if (session_) {
        disconnect(session_, nullptr, this, nullptr);
    }
    session_ = session;

    if (!session_) {
        repoNameValue_->setText(tr("(no repository open)"));
        defaultRemoteValue_->setText(tr("(none)"));
        applyIdentity(LocalIdentity{});
        return;
    }

    connect(session_,
            &RepositorySession::localIdentityUpdated,
            this,
            &RepositoryPage::onLocalIdentityUpdated);
    connect(
        session_, &RepositorySession::remotesUpdated, this, [this] { refreshRepositoryCard(); });

    refreshRepositoryCard();
    loadPerformanceSettings();
    session_->refreshLocalIdentity();
}

void RepositoryPage::refreshRepositoryCard() {
    if (!session_) {
        return;
    }
    repoNameValue_->setText(session_->displayName());

    QString defaultRemote = tr("(none)");
    if (auto remotes = session_->remotes(); remotes && !remotes->empty()) {
        // "origin" is the conventional default; fall back to whichever remote
        // happens to be first when it is absent.
        auto it = std::find_if(remotes->begin(), remotes->end(), [](const RemoteInfo& remote) {
            return remote.name == "origin";
        });
        const RemoteInfo& chosen = it != remotes->end() ? *it : remotes->front();
        defaultRemote = QString::fromStdString(chosen.name);
        if (!chosen.fetchUrl.empty()) {
            defaultRemote += QStringLiteral(" (%1)").arg(QString::fromStdString(chosen.fetchUrl));
        }
    }
    defaultRemoteValue_->setText(defaultRemote);
}

void RepositoryPage::onLocalIdentityUpdated() {
    if (!session_) {
        return;
    }
    if (auto identity = session_->localIdentity()) {
        applyIdentity(*identity);
    }
}

void RepositoryPage::applyIdentity(const LocalIdentity& identity) {
    applyingIdentity_ = true;
    identityOverrideCheck_->setChecked(identity.overridden);
    identityNameEdit_->setText(QString::fromStdString(identity.name));
    identityEmailEdit_->setText(QString::fromStdString(identity.email));
    identityNameEdit_->setEnabled(identity.overridden);
    identityEmailEdit_->setEnabled(identity.overridden);
    applyingIdentity_ = false;
}

void RepositoryPage::onOverrideToggled(bool checked) {
    identityNameEdit_->setEnabled(checked);
    identityEmailEdit_->setEnabled(checked);
    if (applyingIdentity_ || !session_) {
        return;
    }
    if (!checked) {
        session_->clearLocalIdentityOverride();
    }
    // Turning the override on writes nothing yet -- there is nothing to
    // write until the user actually edits a field (onIdentityFieldEdited).
}

void RepositoryPage::onIdentityFieldEdited() {
    if (applyingIdentity_ || !session_ || !identityOverrideCheck_->isChecked()) {
        return;
    }
    const QString name = identityNameEdit_->text();
    const QString email = identityEmailEdit_->text();
    // `git config --local user.email ""` sets the key to an empty string,
    // which git treats as materially different from unset -- it refuses to
    // commit with a confusing error instead of falling back to the global
    // identity. Wait for both fields to be non-empty before writing anything,
    // rather than writing a half-finished override.
    if (name.isEmpty() || email.isEmpty()) {
        return;
    }
    SetLocalIdentityRequest request;
    request.name = name.toStdString();
    request.email = email.toStdString();
    session_->setLocalIdentityOverride(request);
}

QString RepositoryPage::settingsKeyPrefix() const {
    if (!session_) {
        return QString();
    }
    QString path = QString::fromStdString(session_->paths().commandDir().string());
    path.replace(QLatin1Char('/'), QLatin1Char('_'));
    path.replace(QLatin1Char('\\'), QLatin1Char('_'));
    path.replace(QLatin1Char(':'), QLatin1Char('_'));
    return QStringLiteral("repositoryPerf/%1/").arg(path);
}

void RepositoryPage::loadPerformanceSettings() {
    const QString prefix = settingsKeyPrefix();
    if (prefix.isEmpty()) {
        return;
    }
    QSettings settings;
    const bool largeRepoMode =
        settings.value(prefix + QStringLiteral("largeRepoMode"), false).toBool();
    const int maxRows =
        settings.value(prefix + QStringLiteral("maxGraphRows"), kDefaultMaxGraphRows).toInt();
    // Default on: the user asked for this to just work without being opted
    // into, and a failed silent fetch (see RepositorySession::fetchRemoteSilently)
    // never surfaces a prompt, so there is no downside to defaulting it on.
    const bool autoFetch =
        settings.value(prefix + QStringLiteral("autoFetchOnOpen"), true).toBool();

    largeRepoModeCheck_->blockSignals(true);
    largeRepoModeCheck_->setChecked(largeRepoMode);
    largeRepoModeCheck_->blockSignals(false);

    maxGraphRowsSpin_->blockSignals(true);
    maxGraphRowsSpin_->setValue(maxRows);
    maxGraphRowsSpin_->blockSignals(false);
    maxGraphRowsSpin_->setEnabled(largeRepoMode);

    autoFetchCheck_->blockSignals(true);
    autoFetchCheck_->setChecked(autoFetch);
    autoFetchCheck_->blockSignals(false);
}

void RepositoryPage::savePerformanceSetting() {
    const QString prefix = settingsKeyPrefix();
    if (prefix.isEmpty()) {
        return;
    }
    QSettings settings;
    settings.setValue(prefix + QStringLiteral("largeRepoMode"), largeRepoModeCheck_->isChecked());
    settings.setValue(prefix + QStringLiteral("maxGraphRows"), maxGraphRowsSpin_->value());
    settings.setValue(prefix + QStringLiteral("autoFetchOnOpen"), autoFetchCheck_->isChecked());
}

}  // namespace gbm
