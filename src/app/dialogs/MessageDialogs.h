#pragma once

#include <QCoreApplication>
#include <QString>
#include <QStringList>

#include <optional>

class QWidget;

namespace gbm::dialogs {

/// Thin, app-styled replacements for the static QMessageBox/QInputDialog
/// entry points. Each opens a plain QDialog whose buttons set the same
/// #primaryButton/#secondaryButton/#dangerButton objectNames the rest of the
/// app already uses (resources/qss/app.qss), so a confirmation reads as part
/// of the app rather than a native OS sheet.
///
/// Not a replacement for every QMessageBox/QInputDialog call site: the
/// handful with three custom-labelled buttons (Discard/Keep/Cancel-style
/// choices, built with QMessageBox::addButton + ActionRole/RejectRole) are
/// bespoke enough that a mechanical swap here would risk silently changing
/// which button means what. Those stay as raw QMessageBox -- they already
/// inherit the QDialog/QLabel/QPushButton rules in app.qss, so they render
/// styled too, just via Qt's own layout rather than these helpers'.

/// A yes/no confirmation. `destructive` puts the accept button in the danger
/// style (delete/clean/reset-style actions) instead of the primary one.
/// Returns true if the user accepted.
bool confirm(QWidget* parent,
             const QString& title,
             const QString& text,
             const QString& acceptText = QObject::tr("OK"),
             bool destructive = false);

/// A single acknowledgement dialog, informational styling.
void info(QWidget* parent, const QString& title, const QString& text);

/// A single acknowledgement dialog, warning styling (amber/attention framing
/// in the text itself -- QSS carries no distinct "warning dialog" chrome).
void warn(QWidget* parent, const QString& title, const QString& text);

/// A single acknowledgement dialog, error styling.
void error(QWidget* parent, const QString& title, const QString& text);

/// Single-line text prompt. Returns std::nullopt if cancelled.
std::optional<QString> promptText(QWidget* parent,
                                  const QString& title,
                                  const QString& label,
                                  const QString& initialValue = QString(),
                                  bool passwordMode = false);

/// Multi-line text prompt (e.g. a commit message or free-form note). Returns
/// std::nullopt if cancelled.
std::optional<QString> promptMultiLineText(QWidget* parent,
                                           const QString& title,
                                           const QString& label,
                                           const QString& initialValue = QString());

/// Integer prompt. Returns std::nullopt if cancelled.
std::optional<int> promptInt(QWidget* parent,
                             const QString& title,
                             const QString& label,
                             int initialValue,
                             int minValue,
                             int maxValue);

/// Fixed-choice prompt (a styled equivalent of QInputDialog::getItem).
/// Returns std::nullopt if cancelled.
std::optional<QString> promptChoice(QWidget* parent,
                                    const QString& title,
                                    const QString& label,
                                    const QStringList& choices,
                                    int currentIndex = 0);

}  // namespace gbm::dialogs
