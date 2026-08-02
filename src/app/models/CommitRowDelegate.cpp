#include "app/models/CommitRowDelegate.h"

#include "app/bridge/ThemeManager.h"
#include "app/models/CommitListModel.h"
#include "app/models/PillPainter.h"
#include "app/theme/Metrics.h"

#include <QFontMetrics>
#include <QPainter>

#include <algorithm>
#include <vector>

namespace gbm {

namespace {

constexpr int kPillFontSize = 11;
constexpr int kSubjectFontSize = kTextSm;
constexpr int kChipGap = kSpace2;
constexpr int kSubjectToChipsGap = kSpace3;

}  // namespace

CommitRowDelegate::CommitRowDelegate(QObject* parent) : QStyledItemDelegate(parent) {}

void CommitRowDelegate::paint(QPainter* painter,
                              const QStyleOptionViewItem& option,
                              const QModelIndex& index) const {
    const bool selected = (option.state & QStyle::State_Selected) != 0;
    const bool hovered = (option.state & QStyle::State_MouseOver) != 0;
    paintRow(painter, option.rect, index, selected, hovered);
}

void CommitRowDelegate::paintRow(QPainter* painter,
                                const QRect& rect,
                                const QModelIndex& index,
                                bool selected,
                                bool hovered) {
    painter->save();
    painter->setRenderHint(QPainter::Antialiasing, true);

    if (selected) {
        painter->fillRect(rect, ThemeManager::color(Token::SurfaceSelected));
    } else if (hovered) {
        painter->fillRect(rect, ThemeManager::color(Token::SurfaceHover));
    }

    const QRect padded = rect.adjusted(kSpace3, 0, -kSpace3, 0);

    // Chips first (right-aligned), so the subject's elide width can be
    // computed from whatever space they leave.
    const QVariant refsVariant = index.data(CommitListModel::RefsRole);
    const QVariantList refs = refsVariant.toList();
    const QFont pillFont = ThemeManager::monoFont(kPillFontSize);
    const QFontMetrics pillMetrics(pillFont);

    struct PositionedChip {
        RefChip chip;
        int width;
    };
    std::vector<PositionedChip> chips;
    chips.reserve(std::min<int>(refs.size(), kMaxChips));
    for (int i = 0; i < refs.size() && static_cast<int>(chips.size()) < kMaxChips; ++i) {
        const RefChip chip = refs[i].value<RefChip>();
        chips.push_back({chip, PillPainter::widthFor(chip.name, pillMetrics)});
    }

    // Drop chips from the end (rather than shrinking every chip) once the
    // running total would eat more than half the cell -- a commit with many
    // refs still leaves the subject legible, and every chip shown is drawn
    // at its natural width rather than a squashed approximation.
    int chipsWidth = 0;
    std::size_t chipsShown = 0;
    for (; chipsShown < chips.size(); ++chipsShown) {
        const int candidate =
            chipsWidth + chips[chipsShown].width + (chipsShown > 0 ? kChipGap : 0);
        if (candidate > padded.width() / 2) {
            break;
        }
        chipsWidth = candidate;
    }
    chips.resize(chipsShown);

    const QFont subjectFont = ThemeManager::uiFont(kSubjectFontSize);
    const QFontMetrics subjectMetrics(subjectFont);
    const int subjectAreaWidth =
        std::max(0, padded.width() - (chips.empty() ? 0 : chipsWidth + kSubjectToChipsGap));
    const QString subject = index.data(Qt::DisplayRole).toString();
    const QString elidedSubject = subjectMetrics.elidedText(subject, Qt::ElideRight, subjectAreaWidth);

    painter->setFont(subjectFont);
    painter->setPen(ThemeManager::color(Token::TextPrimary));
    painter->drawText(QRect(padded.left(), padded.top(), subjectAreaWidth, padded.height()),
                      Qt::AlignVCenter | Qt::AlignLeft,
                      elidedSubject);

    int chipX = padded.right() - chipsWidth;
    for (const auto& entry : chips) {
        const QRect pillRect(chipX,
                             padded.top() + (padded.height() - PillPainter::kHeight) / 2,
                             entry.width,
                             PillPainter::kHeight);
        const PillColors colors = PillPainter::colorsForRef(entry.chip.kind, entry.chip.isHead);
        PillPainter::paint(painter, pillRect, entry.chip.name, pillFont, colors);
        chipX += entry.width + kChipGap;
    }

    painter->restore();
}

}  // namespace gbm
