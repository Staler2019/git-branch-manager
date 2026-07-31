#include "app/bridge/AskpassWatcher.h"

#include "core/base/FsUtil.h"
#include "core/git/AskpassHelper.h"

#include <QTimer>

#include <fstream>

namespace gbm {

AskpassWatcher::AskpassWatcher(QObject* parent) : QObject(parent) {
    timer_ = new QTimer(this);
    timer_->setInterval(150);
    connect(timer_, &QTimer::timeout, this, &AskpassWatcher::poll);
}

AskpassWatcher::~AskpassWatcher() {
    stop();
}

void AskpassWatcher::start(std::filesystem::path dir) {
    stop();
    if (dir.empty()) {
        return;
    }
    dir_ = std::move(dir);
    requestSeen_ = false;
    timer_->start();
}

void AskpassWatcher::stop() {
    timer_->stop();
    if (!dir_.empty()) {
        std::error_code ec;
        std::filesystem::remove_all(dir_, ec);
    }
    dir_.clear();
    requestSeen_ = false;
}

void AskpassWatcher::poll() {
    if (dir_.empty()) {
        return;
    }
    const auto requestPath = dir_ / std::string(askpass::kRequestFile);
    if (requestSeen_) {
        // The client deletes its own request file once it has read a response;
        // seeing it gone is how a second, follow-up prompt gets noticed.
        std::error_code ec;
        if (!std::filesystem::exists(requestPath, ec)) {
            requestSeen_ = false;
        }
        return;
    }

    auto content = fsutil::readSmallFile(requestPath);
    if (!content) {
        return;
    }
    requestSeen_ = true;
    emit promptReceived(QString::fromStdString(*content));
}

void AskpassWatcher::answer(const QString& secret) {
    if (dir_.empty()) {
        return;
    }
    std::ofstream out(dir_ / std::string(askpass::kResponseFile),
                      std::ios::binary | std::ios::trunc);
    out << secret.toStdString();
}

void AskpassWatcher::cancel() {
    if (dir_.empty()) {
        return;
    }
    std::ofstream out(dir_ / std::string(askpass::kCancelFile), std::ios::binary | std::ios::trunc);
    out << "x";
}

}  // namespace gbm
