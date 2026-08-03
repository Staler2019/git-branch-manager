#include "app/dialogs/KeyboardShortcutsDialog.h"

#include "app/bridge/ThemeManager.h"
#include "app/theme/Metrics.h"

#include <QHeaderView>
#include <QPushButton>
#include <QTableWidget>
#include <QTableWidgetItem>
#include <QVBoxLayout>

#include <iterator>

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
    {"Ctrl+3", "Switch to Diff"},
    {"Ctrl+4", "Switch to Repository Settings"},
    {"Ctrl+L", "Toggle operation log"},
    {"Ctrl+/", "Keyboard shortcuts (this dialog)"},
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

    // A striped two-column table (item 10: "each line should have different
    // background color as table") rather than a QGridLayout of plain-text
    // QLabel pairs -- alternatingRowColors picks up the same
    // @surface-sunken stripe every other QTableView in the app already uses.
    auto* table = new QTableWidget(static_cast<int>(std::size(kShortcuts)), 2, this);
    table->setObjectName(QStringLiteral("shortcutsTable"));
    table->setHorizontalHeaderLabels({QStringLiteral("Shortcut"), QStringLiteral("Action")});
    table->verticalHeader()->setVisible(false);
    table->setShowGrid(false);
    table->setAlternatingRowColors(true);
    table->setEditTriggers(QAbstractItemView::NoEditTriggers);
    table->setSelectionMode(QAbstractItemView::NoSelection);
    table->setFocusPolicy(Qt::NoFocus);
    table->horizontalHeader()->setSectionResizeMode(0, QHeaderView::ResizeToContents);
    table->horizontalHeader()->setSectionResizeMode(1, QHeaderView::Stretch);

    int row = 0;
    for (const ShortcutEntry& entry : kShortcuts) {
        auto* keysItem = new QTableWidgetItem(QString::fromLatin1(entry.keys));
        keysItem->setFont(ThemeManager::monoFont(kTextSm));
        table->setItem(row, 0, keysItem);
        table->setItem(row, 1, new QTableWidgetItem(QString::fromLatin1(entry.action)));
        ++row;
    }
    layout->addWidget(table);

    auto* closeButton = new QPushButton(QStringLiteral("Close"), this);
    connect(closeButton, &QPushButton::clicked, this, &QDialog::accept);
    layout->addWidget(closeButton, 0, Qt::AlignRight);

    resize(460, 420);
}

}  // namespace gbm
