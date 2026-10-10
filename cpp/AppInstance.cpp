// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2025-2026 QueMusic Contributors
//
#include "AppInstance.h"

#include <QCoreApplication>
#include <QDebug>
#include <QJSEngine>
#include <QLocalServer>
#include <QLocalSocket>

namespace {

// 二次启动时发给已有实例的命令
const QByteArray kRaiseCommand = QByteArrayLiteral("raise");

// 本地套接字/命名管道的键。带上用户名：多用户同时登录时 /tmp 下的套接字名不能撞。
QString instanceKey()
{
    QString user = qEnvironmentVariable("USER");
    if (user.isEmpty())
        user = qEnvironmentVariable("USERNAME");
    if (user.isEmpty())
        user = QStringLiteral("default");
    return QStringLiteral("BroNekoX.QueMusic.") + user;
}

} // namespace

AppInstance::AppInstance(QObject *parent)
    : QObject(parent)
{
}

AppInstance::~AppInstance()
{
    if (m_server)
        m_server->close();
}

AppInstance *AppInstance::instance()
{
    static AppInstance *instance = nullptr;
    if (!instance) {
        instance = new AppInstance(nullptr);
        // main.cpp 在 QML 引擎之前就创建并持有它，别让引擎在析构时再删一次
        QQmlEngine::setObjectOwnership(instance, QQmlEngine::CppOwnership);
        // 进程级单例不会自己析构：退出时释放一次，让 QLocalServer 顺手删掉
        // 本地套接字文件，不给 /tmp 留残骸
        qAddPostRoutine([]() {
            delete instance;
            instance = nullptr;
        });
    }
    return instance;
}

AppInstance *AppInstance::create(QQmlEngine *qmlEngine, QJSEngine *scriptEngine)
{
    Q_UNUSED(qmlEngine)
    Q_UNUSED(scriptEngine)
    return instance();
}

bool AppInstance::isPrimary() const
{
    return m_primary;
}

bool AppInstance::isRaisePending() const
{
    return m_raisePending;
}

void AppInstance::clearRaisePending()
{
    if (!m_raisePending)
        return;
    m_raisePending = false;
    emit raisePendingChanged();
}

bool AppInstance::listen()
{
    if (m_server)
        return m_primary;

    const QString key = instanceKey();
    // 上一次异常退出可能留下没人监听的套接字文件，先清掉再监听
    QLocalServer::removeServer(key);

    m_server = new QLocalServer(this);
    m_server->setSocketOptions(QLocalServer::UserAccessOption);
    if (!m_server->listen(key)) {
        qWarning() << "[单实例] 本地套接字监听失败，再次启动将无法唤回窗口:"
                   << m_server->errorString();
        m_server->deleteLater();
        m_server = nullptr;
        return false;
    }

    connect(m_server, &QLocalServer::newConnection, this, &AppInstance::handleConnection);
    m_primary = true;
    emit primaryChanged();
    qInfo() << "[单实例] 已持有本地套接字" << key;
    return true;
}

void AppInstance::requestRaise()
{
    m_raisePending = true;
    emit raisePendingChanged();
    emit raiseRequested();
}

void AppInstance::handleConnection()
{
    if (!m_server)
        return;
    while (QLocalSocket *client = m_server->nextPendingConnection()) {
        // 请求很小（"raise"），事件驱动读一次就够；连接由客户端主动断开
        connect(client, &QLocalSocket::readyRead, this, [this, client]() {
            if (client->readAll().startsWith(kRaiseCommand)) {
                qInfo() << "[单实例] 收到唤回主窗口请求";
                requestRaise();
            }
        });
        connect(client, &QLocalSocket::disconnected, client, &QLocalSocket::deleteLater);
    }
}

bool AppInstance::notifyRunningInstance()
{
    QLocalSocket socket;
    socket.connectToServer(instanceKey(), QIODevice::WriteOnly);
    if (!socket.waitForConnected(400))
        return false;   // 没有实例在跑，本进程就是首个实例

    socket.write(kRaiseCommand);
    socket.flush();
    // 注意：flush() 之后数据往往已经写完，此时 waitForBytesWritten() 会返回 false。
    // 只有「还有没写出去的数据」才说明对方不可用（多半正在退出、套接字还没回收），
    // 这时按首个实例处理，免得请求丢了、窗口也回不来。
    if (socket.bytesToWrite() > 0 && !socket.waitForBytesWritten(400)) {
        socket.abort();
        return false;
    }
    socket.disconnectFromServer();
    if (socket.state() != QLocalSocket::UnconnectedState)
        socket.waitForDisconnected(400);
    return true;
}
