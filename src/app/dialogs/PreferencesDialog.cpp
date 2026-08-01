#include "app/dialogs/PreferencesDialog.h"

#include "app/bridge/ThemeManager.h"

#include <QButtonGroup>
#include <QCheckBox>
#include <QFileDialog>
#include <QFrame>
#include <QHBoxLayout>
#include <QLabel>
#include <QLineEdit>
#include <QPushButton>
#include <QRadioButton>
#include <QSettings>
#include <QVBoxLayout>

namespace gbm {

namespace {

constexpr auto kGeneralCloneDirKey = "general/cloneDirectory";
constexpr auto kGeneralConfirmForcePushKey = "general/confirmForcePush";
constexpr auto kGitGlobalNameKey = "git/globalUserName";
constexpr auto kGitGlobalEmailKey = "git/globalUserEmail";
constexpr auto kGitEditorCommandKey = "git/editorCommand";

QFrame* buildSection(QWidget* parent, const QString& title) {
    auto* frame = new QFrame(parent);
    frame->setObjectName(QStringLiteral("gbmPanel"));
    auto* layout = new QVBoxLayout(frame);
    layout->setContentsMargins(14, 10, 14, 10);
    layout->setSpacing(8);

    auto* header = new QLabel(title, frame);
    header->setObjectName(QStringLiteral("gbmPanelHeader"));
    layout->addWidget(header);

    return frame;
}

QHBoxLayout* buildFieldRow(QFrame* section, const QString& label, QLineEdit** field) {
    auto* row = new QHBoxLayout();
    row->addWidget(new QLabel(label, section));
    *field = new QLineEdit(section);
    row->addWidget(*field, 1);
    return row;
}

}  // namespace

PreferencesDialog::PreferencesDialog(QWidget* parent) : QDialog(parent) {
    setWindowTitle(QStringLiteral("Preferences"));
    buildUi();
    loadSettings();
    resize(480, height());
}

void PreferencesDialog::buildUi() {
    auto* outerLayout = new QVBoxLayout(this);
    outerLayout->setSpacing(14);

    // --- General ---------------------------------------------------------------
    QFrame* generalSection = buildSection(this, tr("General"));
    auto* generalLayout = qobject_cast<QVBoxLayout*>(generalSection->layout());

    auto* cloneDirRow = new QHBoxLayout();
    cloneDirRow->addWidget(new QLabel(tr("Default clone directory"), generalSection));
    cloneDirectoryEdit_ = new QLineEdit(generalSection);
    cloneDirRow->addWidget(cloneDirectoryEdit_, 1);
    auto* browseButton = new QPushButton(tr("Browse…"), generalSection);
    cloneDirRow->addWidget(browseButton);
    connect(browseButton, &QPushButton::clicked, this, [this] {
        const QString chosen = QFileDialog::getExistingDirectory(
            this, tr("Choose the default clone directory"), cloneDirectoryEdit_->text());
        if (!chosen.isEmpty()) {
            cloneDirectoryEdit_->setText(chosen);
            saveGeneralAndGitSettings();
        }
    });
    generalLayout->addLayout(cloneDirRow);
    connect(cloneDirectoryEdit_,
            &QLineEdit::editingFinished,
            this,
            &PreferencesDialog::saveGeneralAndGitSettings);

    confirmForcePushCheck_ = new QCheckBox(tr("Confirm before force-push"), generalSection);
    generalLayout->addWidget(confirmForcePushCheck_);
    connect(confirmForcePushCheck_,
            &QCheckBox::toggled,
            this,
            &PreferencesDialog::saveGeneralAndGitSettings);

    outerLayout->addWidget(generalSection);

    // --- Git (global default) ---------------------------------------------------
    QFrame* gitSection = buildSection(this, tr("Git (global default)"));
    auto* gitLayout = qobject_cast<QVBoxLayout*>(gitSection->layout());

    gitLayout->addLayout(buildFieldRow(gitSection, tr("Name"), &gitNameEdit_));
    gitLayout->addLayout(buildFieldRow(gitSection, tr("Email"), &gitEmailEdit_));
    gitLayout->addLayout(
        buildFieldRow(gitSection, tr("External editor command"), &editorCommandEdit_));

    for (QLineEdit* field : {gitNameEdit_, gitEmailEdit_, editorCommandEdit_}) {
        connect(field,
                &QLineEdit::editingFinished,
                this,
                &PreferencesDialog::saveGeneralAndGitSettings);
    }

    outerLayout->addWidget(gitSection);

    // --- Appearance --------------------------------------------------------------
    QFrame* appearanceSection = buildSection(this, tr("Appearance"));
    auto* appearanceLayout = qobject_cast<QVBoxLayout*>(appearanceSection->layout());

    const ThemeId currentTheme = ThemeManager::loadSetting();
    auto* themeGroup = new QButtonGroup(this);
    for (ThemeId theme :
         {ThemeId::DarkTechnical, ThemeId::LightIde, ThemeId::NeutralProfessional}) {
        auto* row = new QRadioButton(ThemeManager::label(theme), appearanceSection);
        row->setChecked(theme == currentTheme);
        themeGroup->addButton(row);
        appearanceLayout->addWidget(row);
        connect(row, &QRadioButton::toggled, this, [this, theme](bool checked) {
            if (checked) {
                emit themeSelected(theme);
            }
        });
    }

    densityCheck_ = new QCheckBox(tr("Compact row density"), appearanceSection);
    densityCheck_->setChecked(ThemeManager::loadDensitySetting() == Density::Compact);
    appearanceLayout->addWidget(densityCheck_);
    connect(densityCheck_, &QCheckBox::toggled, this, [this](bool checked) {
        emit densityToggled(checked);
    });

    outerLayout->addWidget(appearanceSection);

    // --- footer ------------------------------------------------------------------
    auto* doneButton = new QPushButton(tr("Done"), this);
    doneButton->setObjectName(QStringLiteral("primaryButton"));
    connect(doneButton, &QPushButton::clicked, this, &QDialog::accept);
    outerLayout->addWidget(doneButton, 0, Qt::AlignRight);
}

void PreferencesDialog::loadSettings() {
    QSettings settings;
    cloneDirectoryEdit_->setText(settings.value(QLatin1String(kGeneralCloneDirKey)).toString());
    confirmForcePushCheck_->setChecked(
        settings.value(QLatin1String(kGeneralConfirmForcePushKey), true).toBool());
    gitNameEdit_->setText(settings.value(QLatin1String(kGitGlobalNameKey)).toString());
    gitEmailEdit_->setText(settings.value(QLatin1String(kGitGlobalEmailKey)).toString());
    editorCommandEdit_->setText(settings.value(QLatin1String(kGitEditorCommandKey)).toString());
}

void PreferencesDialog::saveGeneralAndGitSettings() {
    QSettings settings;
    settings.setValue(QLatin1String(kGeneralCloneDirKey), cloneDirectoryEdit_->text());
    settings.setValue(QLatin1String(kGeneralConfirmForcePushKey),
                      confirmForcePushCheck_->isChecked());
    settings.setValue(QLatin1String(kGitGlobalNameKey), gitNameEdit_->text());
    settings.setValue(QLatin1String(kGitGlobalEmailKey), gitEmailEdit_->text());
    settings.setValue(QLatin1String(kGitEditorCommandKey), editorCommandEdit_->text());
}

}  // namespace gbm
