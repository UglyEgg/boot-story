// SPDX-License-Identifier: GPL-3.0-or-later

#include "BootStoryBackend.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSet>
#include <QStandardPaths>

#include <utility>

#if defined(Q_OS_UNIX)
#include <signal.h>
#include <unistd.h>
#endif

namespace
{
constexpr int BackendTimeoutMilliseconds = 12'000;
constexpr double MaximumBootDurationMilliseconds = 86'400'000.0;

void configureProcessGroup(QProcess &process)
{
#if defined(Q_OS_UNIX)
    process.setChildProcessModifier([]() {
        ::setpgid(0, 0);
    });
#else
    Q_UNUSED(process);
#endif
}

void cancelProcessTree(QProcess &process)
{
    if (process.state() == QProcess::NotRunning) {
        return;
    }
#if defined(Q_OS_UNIX)
    const qint64 identifier = process.processId();
    if (identifier > 0) {
        ::kill(-static_cast<pid_t>(identifier), SIGKILL);
    }
#endif
    process.kill();
}

bool boundedNumber(const QJsonValue &value, double maximum = MaximumBootDurationMilliseconds)
{
    return value.isDouble() && value.toDouble() >= 0.0 && value.toDouble() <= maximum;
}

bool validateTimedEntries(const QJsonArray &entries, bool requireStageKey)
{
    static const QSet<QString> stageKeys = {
        QStringLiteral("firmware"),
        QStringLiteral("loader"),
        QStringLiteral("kernel"),
        QStringLiteral("initrd"),
        QStringLiteral("userspace"),
    };
    QSet<QString> seenStages;
    for (const QJsonValue &value : entries) {
        if (!value.isObject()) {
            return false;
        }
        const QJsonObject entry = value.toObject();
        if (!boundedNumber(entry.value(QStringLiteral("durationMs")))) {
            return false;
        }
        if (requireStageKey) {
            const QString key = entry.value(QStringLiteral("key")).toString();
            if (!stageKeys.contains(key) || seenStages.contains(key)
                || !entry.value(QStringLiteral("label")).isString()) {
                return false;
            }
            seenStages.insert(key);
        } else if (!entry.value(QStringLiteral("unit")).isString()
                   || !entry.value(QStringLiteral("name")).isString()) {
            return false;
        }
    }
    return true;
}

bool validateNamedUnits(const QJsonArray &entries)
{
    for (const QJsonValue &value : entries) {
        if (!value.isObject()) {
            return false;
        }
        const QJsonObject entry = value.toObject();
        if (!entry.value(QStringLiteral("unit")).isString()
            || entry.value(QStringLiteral("unit")).toString().isEmpty()
            || !entry.value(QStringLiteral("name")).isString()) {
            return false;
        }
    }
    return true;
}

bool validateCoverage(const QJsonObject &coverage)
{
    for (const QString &key : {
             QStringLiteral("criticalPathAvailable"),
             QStringLiteral("activationsAvailable"),
             QStringLiteral("userSessionAvailable"),
             QStringLiteral("failedUnitsAvailable"),
             QStringLiteral("historyAvailable"),
         }) {
        if (!coverage.value(key).isBool()) {
            return false;
        }
    }
    return true;
}

bool validateSnapshot(const QJsonObject &snapshot, QString *reason)
{
    const auto reject = [reason](const QString &message) {
        if (reason) {
            *reason = message;
        }
        return false;
    };
    static const QSet<QString> healthStates = {
        QStringLiteral("attention"),
        QStringLiteral("faster"),
        QStringLiteral("slower"),
        QStringLiteral("steady"),
        QStringLiteral("baseline"),
        QStringLiteral("unknown"),
    };

    if (snapshot.value(QStringLiteral("ok")) != QJsonValue(true)
        || !snapshot.value(QStringLiteral("summary")).isString()
        || !healthStates.contains(snapshot.value(QStringLiteral("health")).toString())
        || !boundedNumber(snapshot.value(QStringLiteral("bootAgeMs")), 10'000'000'000.0)
        || !boundedNumber(snapshot.value(QStringLiteral("timestampMs")), 10'000'000'000'000.0)) {
        return reject(QStringLiteral("the root status fields are invalid"));
    }

    const QJsonObject system = snapshot.value(QStringLiteral("system")).toObject();
    if (system.isEmpty() || system.value(QStringLiteral("available")) != QJsonValue(true)
        || !boundedNumber(system.value(QStringLiteral("totalMs")))
        || !boundedNumber(system.value(QStringLiteral("readyUserspaceMs")))
        || system.value(QStringLiteral("readyTarget")).toString() != QStringLiteral("graphical.target")
        || !system.value(QStringLiteral("stages")).isArray()
        || !validateTimedEntries(system.value(QStringLiteral("stages")).toArray(), true)) {
        return reject(QStringLiteral("the system timing fields are invalid"));
    }

    const QJsonObject userSession = snapshot.value(QStringLiteral("userSession")).toObject();
    if (userSession.isEmpty() || !userSession.value(QStringLiteral("available")).isBool()
        || !boundedNumber(userSession.value(QStringLiteral("totalMs")))
        || !userSession.value(QStringLiteral("stages")).isArray()
        || !validateTimedEntries(userSession.value(QStringLiteral("stages")).toArray(), true)) {
        return reject(QStringLiteral("the user-session timing fields are invalid"));
    }

    for (const QString &key : {QStringLiteral("criticalPath"), QStringLiteral("activations")}) {
        if (!snapshot.value(key).isArray()
            || !validateTimedEntries(snapshot.value(key).toArray(), false)) {
            return reject(QStringLiteral("the %1 entries are invalid").arg(key));
        }
    }
    if (!snapshot.value(QStringLiteral("failedUnits")).isArray()
        || !validateNamedUnits(snapshot.value(QStringLiteral("failedUnits")).toArray())
        || !snapshot.value(QStringLiteral("recentBoots")).isArray()
        || !snapshot.value(QStringLiteral("comparison")).isObject()
        || !snapshot.value(QStringLiteral("coverage")).isObject()
        || !validateCoverage(snapshot.value(QStringLiteral("coverage")).toObject())
        || !boundedNumber(snapshot.value(QStringLiteral("failedUnitCount")), 1'000'000.0)
        || !boundedNumber(snapshot.value(QStringLiteral("criticalPathTotal")), 1'000'000.0)
        || !boundedNumber(snapshot.value(QStringLiteral("activationTotal")), 1'000'000.0)) {
        return reject(QStringLiteral("the collection metadata is invalid"));
    }
    return true;
}
}

BootStoryBackend::BootStoryBackend(QString helperPath, QObject *parent)
    : BootStoryBackend(std::move(helperPath),
                       QStandardPaths::findExecutable(QStringLiteral("systemctl")),
                       parent)
{
}

BootStoryBackend::BootStoryBackend(QString helperPath, QString systemctlPath, QObject *parent)
    : QObject(parent)
    , m_helperPath(std::move(helperPath))
    , m_systemctlPath(std::move(systemctlPath))
{
    m_timeout.setInterval(BackendTimeoutMilliseconds);
    m_timeout.setSingleShot(true);
    connect(&m_timeout, &QTimer::timeout, this, &BootStoryBackend::processTimedOut);
    connect(&m_process, &QProcess::finished, this, &BootStoryBackend::processFinished);
    connect(&m_process, &QProcess::errorOccurred, this, &BootStoryBackend::processError);

    m_historyTimeout.setInterval(BackendTimeoutMilliseconds);
    m_historyTimeout.setSingleShot(true);
    connect(&m_historyTimeout, &QTimer::timeout, this, &BootStoryBackend::historyProcessTimedOut);
    connect(&m_historyProcess, &QProcess::finished, this, &BootStoryBackend::historyProcessFinished);
    connect(&m_historyProcess, &QProcess::errorOccurred, this, &BootStoryBackend::historyProcessError);

    m_unitTimeout.setInterval(BackendTimeoutMilliseconds);
    m_unitTimeout.setSingleShot(true);
    connect(&m_unitTimeout, &QTimer::timeout, this, &BootStoryBackend::unitProcessTimedOut);
    connect(&m_unitProcess, &QProcess::finished, this, &BootStoryBackend::unitProcessFinished);
    connect(&m_unitProcess, &QProcess::errorOccurred, this, &BootStoryBackend::unitProcessError);

    configureProcessGroup(m_process);
    configureProcessGroup(m_historyProcess);
    configureProcessGroup(m_unitProcess);
}

BootStoryBackend::~BootStoryBackend()
{
    cancelProcessTree(m_process);
    cancelProcessTree(m_historyProcess);
    cancelProcessTree(m_unitProcess);
}

QVariantMap BootStoryBackend::snapshot() const
{
    return m_snapshot;
}

bool BootStoryBackend::snapshotStale() const
{
    return m_snapshotStale;
}

bool BootStoryBackend::busy() const
{
    return m_busy;
}

QString BootStoryBackend::errorMessage() const
{
    return m_errorMessage;
}

bool BootStoryBackend::historyCollectionEnabled() const
{
    return m_historyCollectionEnabled;
}

bool BootStoryBackend::historyCollectionAvailable() const
{
    return m_historyCollectionAvailable;
}

bool BootStoryBackend::historyCollectionBusy() const
{
    return m_historyCollectionBusy;
}

QString BootStoryBackend::historyCollectionError() const
{
    return m_historyCollectionError;
}

QVariantMap BootStoryBackend::unitDetails() const
{
    return m_unitDetails;
}

bool BootStoryBackend::unitDetailsBusy() const
{
    return m_unitDetailsBusy;
}

QString BootStoryBackend::unitDetailsError() const
{
    return m_unitDetailsError;
}

void BootStoryBackend::refresh()
{
    if (m_busy) {
        return;
    }

    setError({});
    setBusy(true);
    m_process.setProgram(m_helperPath);
    m_process.setArguments({});
    m_process.start();
    m_timeout.start();
}

void BootStoryBackend::refreshHistoryCollectionStatus()
{
    if (m_historyCollectionBusy) {
        return;
    }
    if (m_systemctlPath.isEmpty()) {
        setHistoryCollectionAvailable(false);
        setHistoryCollectionError(tr("systemctl is unavailable, so automatic history cannot be configured."));
        return;
    }

    startHistoryOperation(HistoryOperation::Query,
                          {QStringLiteral("--user"),
                           QStringLiteral("is-enabled"),
                           QStringLiteral(BOOT_STORY_RECORDER_UNIT)});
}

void BootStoryBackend::setHistoryCollectionEnabled(bool enabled)
{
    if (m_historyCollectionBusy || enabled == m_historyCollectionEnabled) {
        return;
    }
    if (m_systemctlPath.isEmpty()) {
        setHistoryCollectionAvailable(false);
        setHistoryCollectionError(tr("systemctl is unavailable, so automatic history cannot be configured."));
        return;
    }

    startHistoryOperation(enabled ? HistoryOperation::Enable : HistoryOperation::Disable,
                          {QStringLiteral("--user"),
                           enabled ? QStringLiteral("enable") : QStringLiteral("disable"),
                           QStringLiteral("--now"),
                           QStringLiteral(BOOT_STORY_RECORDER_UNIT)});
}

void BootStoryBackend::inspectUnit(const QString &unit)
{
    static const QRegularExpression validUnit(
        QStringLiteral("^[A-Za-z0-9_.@\\\\x:-]+\\.(service|mount|automount|swap|socket|target|device|timer|path|slice|scope)$"));
    clearUnitDetails();
    if (unit.size() > 256 || !validUnit.match(unit).hasMatch()) {
        setUnitDetailsError(tr("That unit name is not safe to inspect."));
        return;
    }

    setUnitDetailsBusy(true);
    m_unitProcess.setProgram(m_helperPath);
    m_unitProcess.setArguments({QStringLiteral("--inspect-unit"), unit});
    m_unitProcess.start();
    m_unitTimeout.start();
}

void BootStoryBackend::clearUnitDetails()
{
    if (m_unitDetailsBusy) {
        m_unitTimeout.stop();
        setUnitDetailsBusy(false);
        cancelProcessTree(m_unitProcess);
    }
    setUnitDetails({});
    setUnitDetailsError({});
}

void BootStoryBackend::processFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    if (!m_busy) {
        return;
    }

    m_timeout.stop();
    const QByteArray output = m_process.readAllStandardOutput();
    const QByteArray diagnostic = m_process.readAllStandardError().trimmed();
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(output, &parseError);

    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        if (exitStatus != QProcess::NormalExit || exitCode != 0) {
            fail(diagnostic.isEmpty() ? tr("The boot collector exited unsuccessfully.") : QString::fromUtf8(diagnostic));
            return;
        }
        fail(tr("The boot collector returned unreadable data."));
        return;
    }

    const QJsonObject object = document.object();
    if (!object.value(QStringLiteral("ok")).toBool()) {
        fail(object.value(QStringLiteral("error")).toString(tr("Boot timing is unavailable.")));
        return;
    }
    if (exitStatus != QProcess::NormalExit || exitCode != 0) {
        fail(diagnostic.isEmpty() ? tr("The boot collector exited unsuccessfully.") : QString::fromUtf8(diagnostic));
        return;
    }

    QString validationError;
    if (!validateSnapshot(object, &validationError)) {
        fail(tr("The boot collector returned incomplete data: %1").arg(validationError));
        return;
    }

    m_snapshot = object.toVariantMap();
    Q_EMIT snapshotChanged();
    setSnapshotStale(false);
    setBusy(false);
}

void BootStoryBackend::processError(QProcess::ProcessError error)
{
    if (!m_busy || error == QProcess::Timedout) {
        return;
    }
    fail(tr("Could not start the boot collector: %1").arg(m_process.errorString()));
}

void BootStoryBackend::processTimedOut()
{
    if (!m_busy) {
        return;
    }
    cancelProcessTree(m_process);
    fail(tr("The boot collector timed out."));
}

void BootStoryBackend::historyProcessFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    if (m_historyOperation == HistoryOperation::None) {
        return;
    }

    m_historyTimeout.stop();
    const HistoryOperation operation = m_historyOperation;
    m_historyOperation = HistoryOperation::None;
    const QString output = QString::fromUtf8(m_historyProcess.readAllStandardOutput()).trimmed().toLower();
    const QString diagnostic = QString::fromUtf8(m_historyProcess.readAllStandardError()).trimmed();

    if (operation == HistoryOperation::Query) {
        const bool recognizedState = output == QStringLiteral("enabled")
            || output == QStringLiteral("enabled-runtime")
            || output == QStringLiteral("disabled")
            || output == QStringLiteral("masked")
            || output == QStringLiteral("masked-runtime")
            || output == QStringLiteral("static")
            || output == QStringLiteral("indirect")
            || output == QStringLiteral("generated")
            || output == QStringLiteral("transient")
            || output == QStringLiteral("linked")
            || output == QStringLiteral("linked-runtime")
            || output == QStringLiteral("alias");
        if (exitStatus != QProcess::NormalExit || !recognizedState) {
            setHistoryCollectionAvailable(false);
            setHistoryCollectionEnabledState(false);
            failHistoryOperation(output == QStringLiteral("not-found")
                                     ? tr("The automatic history service is not installed.")
                                     : (diagnostic.isEmpty()
                                            ? tr("Could not read the automatic history setting.")
                                            : diagnostic));
            return;
        }

        setHistoryCollectionAvailable(true);
        setHistoryCollectionEnabledState(output == QStringLiteral("enabled")
                                         || output == QStringLiteral("enabled-runtime"));
        setHistoryCollectionError({});
        setHistoryCollectionBusy(false);
        return;
    }

    if (exitStatus != QProcess::NormalExit || exitCode != 0) {
        failHistoryOperation(diagnostic.isEmpty()
                                 ? tr("Could not change automatic history collection.")
                                 : diagnostic);
        return;
    }

    setHistoryCollectionAvailable(true);
    setHistoryCollectionEnabledState(operation == HistoryOperation::Enable);
    setHistoryCollectionError({});
    setHistoryCollectionBusy(false);
}

void BootStoryBackend::historyProcessError(QProcess::ProcessError error)
{
    if (m_historyOperation == HistoryOperation::None || error == QProcess::Timedout) {
        return;
    }

    m_historyTimeout.stop();
    m_historyOperation = HistoryOperation::None;
    if (error == QProcess::FailedToStart) {
        setHistoryCollectionAvailable(false);
        setHistoryCollectionEnabledState(false);
    }
    failHistoryOperation(tr("Could not run systemctl: %1").arg(m_historyProcess.errorString()));
}

void BootStoryBackend::historyProcessTimedOut()
{
    if (m_historyOperation == HistoryOperation::None) {
        return;
    }
    cancelProcessTree(m_historyProcess);
    m_historyOperation = HistoryOperation::None;
    failHistoryOperation(tr("Changing the automatic history setting timed out."));
}

void BootStoryBackend::unitProcessFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    if (!m_unitDetailsBusy) {
        return;
    }

    m_unitTimeout.stop();
    const QByteArray output = m_unitProcess.readAllStandardOutput();
    const QByteArray diagnostic = m_unitProcess.readAllStandardError().trimmed();
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(output, &parseError);

    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        if (exitStatus != QProcess::NormalExit || exitCode != 0) {
            failUnitInspection(diagnostic.isEmpty()
                                   ? tr("The unit inspector exited unsuccessfully.")
                                   : QString::fromUtf8(diagnostic));
            return;
        }
        failUnitInspection(tr("The unit inspector returned unreadable data."));
        return;
    }

    const QVariantMap details = document.object().toVariantMap();
    if (!details.value(QStringLiteral("ok")).toBool()) {
        failUnitInspection(details.value(QStringLiteral("error"), tr("Unit details are unavailable.")).toString());
        return;
    }
    if (exitStatus != QProcess::NormalExit || exitCode != 0) {
        failUnitInspection(diagnostic.isEmpty()
                               ? tr("The unit inspector exited unsuccessfully.")
                               : QString::fromUtf8(diagnostic));
        return;
    }

    setUnitDetails(details);
    setUnitDetailsBusy(false);
}

void BootStoryBackend::unitProcessError(QProcess::ProcessError error)
{
    if (!m_unitDetailsBusy || error == QProcess::Timedout) {
        return;
    }
    m_unitTimeout.stop();
    failUnitInspection(tr("Could not start the unit inspector: %1").arg(m_unitProcess.errorString()));
}

void BootStoryBackend::unitProcessTimedOut()
{
    if (!m_unitDetailsBusy) {
        return;
    }
    cancelProcessTree(m_unitProcess);
    failUnitInspection(tr("The unit inspector timed out."));
}

void BootStoryBackend::setBusy(bool busy)
{
    if (m_busy == busy) {
        return;
    }
    m_busy = busy;
    Q_EMIT busyChanged();
}

void BootStoryBackend::setSnapshotStale(bool stale)
{
    if (m_snapshotStale == stale) {
        return;
    }
    m_snapshotStale = stale;
    Q_EMIT snapshotStaleChanged();
}

void BootStoryBackend::setError(QString message)
{
    if (m_errorMessage == message) {
        return;
    }
    m_errorMessage = std::move(message);
    Q_EMIT errorMessageChanged();
}

void BootStoryBackend::fail(QString message)
{
    if (!m_snapshot.isEmpty()) {
        setSnapshotStale(true);
    }
    setError(std::move(message));
    setBusy(false);
}

void BootStoryBackend::startHistoryOperation(HistoryOperation operation, const QStringList &arguments)
{
    setHistoryCollectionError({});
    setHistoryCollectionBusy(true);
    m_historyOperation = operation;
    m_historyProcess.setProgram(m_systemctlPath);
    m_historyProcess.setArguments(arguments);
    m_historyProcess.start();
    m_historyTimeout.start();
}

void BootStoryBackend::setHistoryCollectionEnabledState(bool enabled)
{
    if (m_historyCollectionEnabled == enabled) {
        return;
    }
    m_historyCollectionEnabled = enabled;
    Q_EMIT historyCollectionEnabledChanged();
}

void BootStoryBackend::setHistoryCollectionAvailable(bool available)
{
    if (m_historyCollectionAvailable == available) {
        return;
    }
    m_historyCollectionAvailable = available;
    Q_EMIT historyCollectionAvailableChanged();
}

void BootStoryBackend::setHistoryCollectionBusy(bool busy)
{
    if (m_historyCollectionBusy == busy) {
        return;
    }
    m_historyCollectionBusy = busy;
    Q_EMIT historyCollectionBusyChanged();
}

void BootStoryBackend::setHistoryCollectionError(QString message)
{
    if (m_historyCollectionError == message) {
        return;
    }
    m_historyCollectionError = std::move(message);
    Q_EMIT historyCollectionErrorChanged();
}

void BootStoryBackend::failHistoryOperation(QString message)
{
    setHistoryCollectionError(std::move(message));
    setHistoryCollectionBusy(false);
}

void BootStoryBackend::setUnitDetails(QVariantMap details)
{
    if (m_unitDetails == details) {
        return;
    }
    m_unitDetails = std::move(details);
    Q_EMIT unitDetailsChanged();
}

void BootStoryBackend::setUnitDetailsBusy(bool busy)
{
    if (m_unitDetailsBusy == busy) {
        return;
    }
    m_unitDetailsBusy = busy;
    Q_EMIT unitDetailsBusyChanged();
}

void BootStoryBackend::setUnitDetailsError(QString message)
{
    if (m_unitDetailsError == message) {
        return;
    }
    m_unitDetailsError = std::move(message);
    Q_EMIT unitDetailsErrorChanged();
}

void BootStoryBackend::failUnitInspection(QString message)
{
    setUnitDetailsError(std::move(message));
    setUnitDetailsBusy(false);
}
