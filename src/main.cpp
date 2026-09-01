// SPDX-License-Identifier: GPL-3.0-or-later

#include "backend/BootStoryBackend.h"

#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QGuiApplication>
#include <QIcon>
#include <QFileInfo>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QTimer>

int main(int argc, char *argv[])
{
    QGuiApplication application(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("Boot Story"));
    QGuiApplication::setApplicationDisplayName(QStringLiteral("Boot Story"));
    QGuiApplication::setApplicationVersion(QStringLiteral(BOOT_STORY_VERSION));
    QGuiApplication::setOrganizationName(QStringLiteral("uglyegg"));
    QGuiApplication::setOrganizationDomain(QStringLiteral("entropy.quest"));
    QGuiApplication::setDesktopFileName(QStringLiteral("quest.entropy.bootstory"));
    QGuiApplication::setWindowIcon(QIcon::fromTheme(QStringLiteral("quest.entropy.bootstory")));
    QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"));

    QCommandLineParser parser;
    parser.setApplicationDescription(QStringLiteral("A visual story of the current Linux boot"));
    parser.addHelpOption();
    parser.addVersionOption();
    const QString relativeHelper = QGuiApplication::applicationDirPath()
        + QStringLiteral("/../libexec/boot-story/boot-story-snapshot");
    const QString defaultHelper = QFileInfo::exists(relativeHelper)
        ? QFileInfo(relativeHelper).canonicalFilePath()
        : QStringLiteral(BOOT_STORY_HELPER_PATH);
    QCommandLineOption helperOption(
        QStringLiteral("helper"),
        QStringLiteral("Use an alternate boot collector (development/testing)."),
        QStringLiteral("path"),
        defaultHelper);
    parser.addOption(helperOption);
    parser.process(application);

    BootStoryBackend backend(parser.value(helperOption));
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("bootBackend"), &backend);
    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));
    if (engine.rootObjects().isEmpty()) {
        return 1;
    }

    QTimer::singleShot(0, &backend, [&backend]() {
        backend.refresh();
        backend.refreshHistoryCollectionStatus();
    });
    return application.exec();
}
