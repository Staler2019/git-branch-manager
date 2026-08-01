#include "app/dialogs/KeyboardShortcutsDialog.h"

#include <QFont>
#include <QGridLayout>
#include <QLabel>
#include <QPushButton>
#include <QVBoxLayout>

namespace gbm {

namespace {

struct ShortcutEntry {
    const char* keys;
    const char* action;
};

constexpr ShortcutEntry kShortcuts[] = {
    {"Ctrl+W", "Close repository"},
    {"F5", "Refresh"},
    {"Ctrl+F5", "Refresh (rescan everything)"},
    {"Ctrl+1", "Switch to History"},
    {"Ctrl+2", "Switch to Working Copy"},
    {"Ctrl+L", "Toggle operation log"},
    {"Ctrl+Shift+O", "Switch to selected branch"},
    {"Ctrl+Shift+M", "Merge selected branch into current"},
    {"Ctrl+Shift+C", "Cherry-pick selected commit(s)"},
    {"Ctrl+Shift+F", "Fetch"},
    {"Ctrl+Shift+L", "Pull"},
    {"Ctrl+Shift+P", "Push"},
    {"Ctrl+Z", "Undo last operation"},
};

}  // namespace

KeyboardShortcutsDialog::KeyboardShortcutsDialog(QWidget* parent) : QDialog(parent) {
    setWindowTitle(QStringLiteral("Keyboard shortcuts"));
    auto* layout = new QVBoxLayout(this);

    auto* grid = new QGridLayout();
    int row = 0;
    for (const ShortcutEntry& entry : kShortcuts) {
        auto* keysLabel = new QLabel(QString::fromLatin1(entry.keys), this);
        QFont monoFont = keysLabel->font();
        monoFont.setFamily(QStringLiteral("monospace"));
        keysLabel->setFont(monoFont);
        grid->addWidget(keysLabel, row, 0);
        grid->addWidget(new QLabel(QString::fromLatin1(entry.action), this), row, 1);
        ++row;
    }
    layout->addLayout(grid);

    auto* closeButton = new QPushButton(QStringLiteral("Close"), this);
    connect(closeButton, &QPushButton::clicked, this, &QDialog::accept);
    layout->addWidget(closeButton, 0, Qt::AlignRight);

    resize(420, 360);
}

}  // namespace gbm
