// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QProcess>
#include <QTimer>
#include <QVariantMap>

class BootStoryBackend final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantMap snapshot READ snapshot NOTIFY snapshotChanged)
    Q_PROPERTY(bool snapshotStale READ snapshotStale NOTIFY snapshotStaleChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorMessageChanged)
    Q_PROPERTY(bool historyCollectionEnabled READ historyCollectionEnabled NOTIFY historyCollectionEnabledChanged)
    Q_PROPERTY(bool historyCollectionAvailable READ historyCollectionAvailable NOTIFY historyCollectionAvailableChanged)
    Q_PROPERTY(bool historyCollectionBusy READ historyCollectionBusy NOTIFY historyCollectionBusyChanged)
    Q_PROPERTY(QString historyCollectionError READ historyCollectionError NOTIFY historyCollectionErrorChanged)
    Q_PROPERTY(QVariantMap unitDetails READ unitDetails NOTIFY unitDetailsChanged)
    Q_PROPERTY(bool unitDetailsBusy READ unitDetailsBusy NOTIFY unitDetailsBusyChanged)
    Q_PROPERTY(QString unitDetailsError READ unitDetailsError NOTIFY unitDetailsErrorChanged)

public:
    explicit BootStoryBackend(QString helperPath, QObject *parent = nullptr);
    BootStoryBackend(QString helperPath, QString systemctlPath, QObject *parent);
    ~BootStoryBackend() override;

    [[nodiscard]] QVariantMap snapshot() const;
    [[nodiscard]] bool snapshotStale() const;
    [[nodiscard]] bool busy() const;
    [[nodiscard]] QString errorMessage() const;
    [[nodiscard]] bool historyCollectionEnabled() const;
    [[nodiscard]] bool historyCollectionAvailable() const;
    [[nodiscard]] bool historyCollectionBusy() const;
    [[nodiscard]] QString historyCollectionError() const;
    [[nodiscard]] QVariantMap unitDetails() const;
    [[nodiscard]] bool unitDetailsBusy() const;
    [[nodiscard]] QString unitDetailsError() const;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void refreshHistoryCollectionStatus();
    Q_INVOKABLE void setHistoryCollectionEnabled(bool enabled);
    Q_INVOKABLE void inspectUnit(const QString &unit);
    Q_INVOKABLE void clearUnitDetails();

Q_SIGNALS:
    void snapshotChanged();
    void snapshotStaleChanged();
    void busyChanged();
    void errorMessageChanged();
    void historyCollectionEnabledChanged();
    void historyCollectionAvailableChanged();
    void historyCollectionBusyChanged();
    void historyCollectionErrorChanged();
    void unitDetailsChanged();
    void unitDetailsBusyChanged();
    void unitDetailsErrorChanged();

private Q_SLOTS:
    void processFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void processError(QProcess::ProcessError error);
    void processTimedOut();
    void historyProcessFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void historyProcessError(QProcess::ProcessError error);
    void historyProcessTimedOut();
    void unitProcessFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void unitProcessError(QProcess::ProcessError error);
    void unitProcessTimedOut();

private:
    enum class HistoryOperation {
        None,
        Query,
        Enable,
        Disable,
    };

    void setBusy(bool busy);
    void setSnapshotStale(bool stale);
    void setError(QString message);
    void fail(QString message);
    void startHistoryOperation(HistoryOperation operation, const QStringList &arguments);
    void setHistoryCollectionEnabledState(bool enabled);
    void setHistoryCollectionAvailable(bool available);
    void setHistoryCollectionBusy(bool busy);
    void setHistoryCollectionError(QString message);
    void failHistoryOperation(QString message);
    void setUnitDetails(QVariantMap details);
    void setUnitDetailsBusy(bool busy);
    void setUnitDetailsError(QString message);
    void failUnitInspection(QString message);

    QString m_helperPath;
    QVariantMap m_snapshot;
    bool m_snapshotStale = false;
    QString m_errorMessage;
    bool m_busy = false;
    QProcess m_process;
    QTimer m_timeout;
    QString m_systemctlPath;
    QString m_historyCollectionError;
    bool m_historyCollectionEnabled = false;
    bool m_historyCollectionAvailable = false;
    bool m_historyCollectionBusy = false;
    HistoryOperation m_historyOperation = HistoryOperation::None;
    QProcess m_historyProcess;
    QTimer m_historyTimeout;
    QVariantMap m_unitDetails;
    QString m_unitDetailsError;
    bool m_unitDetailsBusy = false;
    QProcess m_unitProcess;
    QTimer m_unitTimeout;
};
