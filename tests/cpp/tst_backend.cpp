// SPDX-License-Identifier: GPL-3.0-or-later

#include "backend/BootStoryBackend.h"

#include <QFile>
#include <QTemporaryDir>
#include <QtTest>

class BackendTest final : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void historyCollectionCanBeQueriedAndChanged();
    void validSnapshotBecomesStaleAfterStructuredRefreshFailure();
    void invalidSnapshotSchemaIsRejected();
    void selectedUnitCanBeInspected();
    void clearingInspectionCancelsTheHelperProcessTree();
    void unsafeUnitIsRejectedBeforeLaunch();
};

void BackendTest::historyCollectionCanBeQueriedAndChanged()
{
    QTemporaryDir temporaryDirectory;
    QVERIFY(temporaryDirectory.isValid());

    const QString statePath = temporaryDirectory.filePath(QStringLiteral("state"));
    QFile stateFile(statePath);
    QVERIFY(stateFile.open(QIODevice::WriteOnly));
    QCOMPARE(stateFile.write("disabled\n"), 9);
    stateFile.close();

    const QString systemctlPath = temporaryDirectory.filePath(QStringLiteral("systemctl"));
    QFile systemctlFile(systemctlPath);
    QVERIFY(systemctlFile.open(QIODevice::WriteOnly));
    const QByteArray script = R"(#!/bin/sh
set -eu
case "${2:-}" in
    is-enabled)
        test "${3:-}" = boot-story-record.timer
        state=$(sed -n '1p' "$BOOT_STORY_TEST_STATE")
        printf '%s\n' "$state"
        test "$state" = enabled
        ;;
    enable)
        test "${3:-}" = --now
        test "${4:-}" = boot-story-record.timer
        printf 'enabled\n' > "$BOOT_STORY_TEST_STATE"
        ;;
    disable)
        test "${3:-}" = --now
        test "${4:-}" = boot-story-record.timer
        printf 'disabled\n' > "$BOOT_STORY_TEST_STATE"
        ;;
    *)
        exit 2
        ;;
esac
)";
    QCOMPARE(systemctlFile.write(script), script.size());
    systemctlFile.close();
    QVERIFY(systemctlFile.setPermissions(QFileDevice::ReadOwner
                                         | QFileDevice::WriteOwner
                                         | QFileDevice::ExeOwner));
    QVERIFY(qputenv("BOOT_STORY_TEST_STATE", statePath.toUtf8()));

    BootStoryBackend backend(QStringLiteral("/unused/helper"), systemctlPath, nullptr);
    backend.refreshHistoryCollectionStatus();
    QTRY_VERIFY_WITH_TIMEOUT(!backend.historyCollectionBusy(), 3000);
    QVERIFY(backend.historyCollectionAvailable());
    QVERIFY(!backend.historyCollectionEnabled());
    QVERIFY(backend.historyCollectionError().isEmpty());

    backend.setHistoryCollectionEnabled(true);
    QTRY_VERIFY_WITH_TIMEOUT(!backend.historyCollectionBusy(), 3000);
    QVERIFY(backend.historyCollectionEnabled());
    QVERIFY(backend.historyCollectionError().isEmpty());

    backend.setHistoryCollectionEnabled(false);
    QTRY_VERIFY_WITH_TIMEOUT(!backend.historyCollectionBusy(), 3000);
    QVERIFY(!backend.historyCollectionEnabled());
    QVERIFY(backend.historyCollectionError().isEmpty());

    qunsetenv("BOOT_STORY_TEST_STATE");
}

void BackendTest::validSnapshotBecomesStaleAfterStructuredRefreshFailure()
{
    QTemporaryDir temporaryDirectory;
    QVERIFY(temporaryDirectory.isValid());

    const QString statePath = temporaryDirectory.filePath(QStringLiteral("called"));
    const QString helperPath = temporaryDirectory.filePath(QStringLiteral("boot-story-snapshot"));
    QFile helperFile(helperPath);
    QVERIFY(helperFile.open(QIODevice::WriteOnly));
    const QByteArray script = R"(#!/bin/sh
set -eu
if test ! -e "$BOOT_STORY_TEST_STATE"; then
    : > "$BOOT_STORY_TEST_STATE"
    printf '%s\n' '{"ok":true,"timestampMs":1700000000000,"bootAgeMs":1000,"health":"baseline","summary":"Ready","system":{"available":true,"totalMs":10000,"readyTarget":"graphical.target","readyUserspaceMs":9000,"stages":[{"key":"userspace","label":"Services","durationMs":10000}]},"userSession":{"available":false,"totalMs":0,"stages":[]},"criticalPath":[],"criticalPathTotal":0,"activations":[],"activationTotal":0,"failedUnits":[],"failedUnitCount":0,"comparison":{},"recentBoots":[],"coverage":{"criticalPathAvailable":true,"activationsAvailable":true,"userSessionAvailable":false,"failedUnitsAvailable":true,"historyAvailable":true}}'
    exit 0
fi
printf '%s\n' '{"ok":false,"error":"collector detail"}'
exit 1
)";
    QCOMPARE(helperFile.write(script), script.size());
    helperFile.close();
    QVERIFY(helperFile.setPermissions(QFileDevice::ReadOwner
                                      | QFileDevice::WriteOwner
                                      | QFileDevice::ExeOwner));
    QVERIFY(qputenv("BOOT_STORY_TEST_STATE", statePath.toUtf8()));

    BootStoryBackend backend(helperPath, QStringLiteral("/unused/systemctl"), nullptr);
    backend.refresh();
    QTRY_VERIFY_WITH_TIMEOUT(!backend.busy(), 3000);
    QVERIFY(backend.snapshot().value(QStringLiteral("ok")).toBool());
    QVERIFY(!backend.snapshotStale());

    backend.refresh();
    QTRY_VERIFY_WITH_TIMEOUT(!backend.busy(), 3000);
    QVERIFY(backend.snapshotStale());
    QCOMPARE(backend.errorMessage(), QStringLiteral("collector detail"));
    qunsetenv("BOOT_STORY_TEST_STATE");
}

void BackendTest::invalidSnapshotSchemaIsRejected()
{
    QTemporaryDir temporaryDirectory;
    QVERIFY(temporaryDirectory.isValid());
    const QString helperPath = temporaryDirectory.filePath(QStringLiteral("boot-story-snapshot"));
    QFile helperFile(helperPath);
    QVERIFY(helperFile.open(QIODevice::WriteOnly));
    const QByteArray script = R"(#!/bin/sh
printf '%s\n' '{"ok":true,"summary":"missing required fields"}'
)";
    QCOMPARE(helperFile.write(script), script.size());
    helperFile.close();
    QVERIFY(helperFile.setPermissions(QFileDevice::ReadOwner
                                      | QFileDevice::WriteOwner
                                      | QFileDevice::ExeOwner));

    BootStoryBackend backend(helperPath, QStringLiteral("/unused/systemctl"), nullptr);
    backend.refresh();
    QTRY_VERIFY_WITH_TIMEOUT(!backend.busy(), 3000);
    QVERIFY(backend.snapshot().isEmpty());
    QVERIFY(backend.errorMessage().contains(QStringLiteral("incomplete data")));
}

void BackendTest::selectedUnitCanBeInspected()
{
    QTemporaryDir temporaryDirectory;
    QVERIFY(temporaryDirectory.isValid());

    const QString helperPath = temporaryDirectory.filePath(QStringLiteral("boot-story-snapshot"));
    QFile helperFile(helperPath);
    QVERIFY(helperFile.open(QIODevice::WriteOnly));
    const QByteArray script = R"(#!/bin/sh
set -eu
test "${1:-}" = --inspect-unit
test "${2:-}" = demo.service
printf '%s\n' '{"ok":true,"unit":"demo.service","name":"Demo","description":"Demonstration service","activeState":"active","subState":"running","unitFileState":"enabled","result":"success","relationships":{"pulledInBy":[{"unit":"graphical.target","name":"Graphical"}],"bringsIn":[],"orderedAfter":[]}}'
)";
    QCOMPARE(helperFile.write(script), script.size());
    helperFile.close();
    QVERIFY(helperFile.setPermissions(QFileDevice::ReadOwner
                                      | QFileDevice::WriteOwner
                                      | QFileDevice::ExeOwner));

    BootStoryBackend backend(helperPath, QStringLiteral("/unused/systemctl"), nullptr);
    backend.inspectUnit(QStringLiteral("demo.service"));
    QVERIFY(backend.unitDetailsBusy());
    QTRY_VERIFY_WITH_TIMEOUT(!backend.unitDetailsBusy(), 3000);
    QVERIFY(backend.unitDetailsError().isEmpty());
    QCOMPARE(backend.unitDetails().value(QStringLiteral("unit")).toString(), QStringLiteral("demo.service"));
    QCOMPARE(backend.unitDetails().value(QStringLiteral("activeState")).toString(), QStringLiteral("active"));
}

void BackendTest::clearingInspectionCancelsTheHelperProcessTree()
{
    QTemporaryDir temporaryDirectory;
    QVERIFY(temporaryDirectory.isValid());

    const QString startedPath = temporaryDirectory.filePath(QStringLiteral("started"));
    const QString completedPath = temporaryDirectory.filePath(QStringLiteral("completed"));
    const QString helperPath = temporaryDirectory.filePath(QStringLiteral("boot-story-snapshot"));
    QFile helperFile(helperPath);
    QVERIFY(helperFile.open(QIODevice::WriteOnly));
    const QByteArray script = R"(#!/bin/sh
set -eu
: > "$BOOT_STORY_TEST_STARTED"
(sleep 2; : > "$BOOT_STORY_TEST_COMPLETED") &
wait
)";
    QCOMPARE(helperFile.write(script), script.size());
    helperFile.close();
    QVERIFY(helperFile.setPermissions(QFileDevice::ReadOwner
                                      | QFileDevice::WriteOwner
                                      | QFileDevice::ExeOwner));
    QVERIFY(qputenv("BOOT_STORY_TEST_STARTED", startedPath.toUtf8()));
    QVERIFY(qputenv("BOOT_STORY_TEST_COMPLETED", completedPath.toUtf8()));

    BootStoryBackend backend(helperPath, QStringLiteral("/unused/systemctl"), nullptr);
    backend.inspectUnit(QStringLiteral("demo.service"));
    QTRY_VERIFY_WITH_TIMEOUT(QFile::exists(startedPath), 1000);
    backend.clearUnitDetails();
    QVERIFY(!backend.unitDetailsBusy());
    QTest::qWait(2200);
    QVERIFY(!QFile::exists(completedPath));

    qunsetenv("BOOT_STORY_TEST_STARTED");
    qunsetenv("BOOT_STORY_TEST_COMPLETED");
}

void BackendTest::unsafeUnitIsRejectedBeforeLaunch()
{
    BootStoryBackend backend(QStringLiteral("/path/that/must/not/run"),
                             QStringLiteral("/unused/systemctl"),
                             nullptr);
    backend.inspectUnit(QStringLiteral("../demo.service"));
    QVERIFY(!backend.unitDetailsBusy());
    QVERIFY(backend.unitDetails().isEmpty());
    QVERIFY(backend.unitDetailsError().contains(QStringLiteral("not safe")));
}

QTEST_GUILESS_MAIN(BackendTest)

#include "tst_backend.moc"
