// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2025-2026 QueMusic Contributors
//
// 进程单实例守卫 + 「唤回主窗口」通道。
//
// 背景：开启后台播放后，关闭按钮只隐藏窗口、进程与音频线程继续跑；而没有系统托盘的
// 环境（GNOME 默认、精简 WM）没有托盘图标可点，窗口一藏用户就找不回来了。
// 这里用 QLocalServer 做单实例：首个进程监听，之后每次启动 QueMusic 都把
// 「唤回窗口」请求发给已在跑的进程，然后自己立刻退出。
#ifndef APPINSTANCE_H
#define APPINSTANCE_H

#include <QObject>
#include <QString>
#include <QQmlEngine>
#include <QtQml/qqmlregistration.h>

class QJSEngine;
class QLocalServer;

// ⚠️ 构造函数【绝不能】带默认参数：QML 单例的 singletonConstructionMode() 里
// is_default_constructible 优先于 HasSingletonFactory，写成 X(QObject *parent = nullptr)
// 会让引擎走默认构造分支、create() 永不执行（同类陷阱见 cpp/AppModels.h 的说明）。
class AppInstance : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool primary READ isPrimary NOTIFY primaryChanged)                 // 本进程是否持有监听
    Q_PROPERTY(bool raisePending READ isRaisePending NOTIFY raisePendingChanged)  // 启动瞬间到达、QML 还没接上的唤回请求

public:
    // QML 单例工厂：main.cpp 会提前调用 instance() 抢占监听，
    // 之后 QML 首次访问 AppInstance 时复用同一对象。
    static AppInstance *create(QQmlEngine *qmlEngine, QJSEngine *scriptEngine);

    // 进程内唯一实例（进程级生命周期，不交给 QML 引擎析构）
    static AppInstance *instance();

    bool isPrimary() const;
    bool isRaisePending() const;

    Q_INVOKABLE void clearRaisePending();

    // 已有实例在跑时把唤回请求发给它并返回 true（调用方应立即退出）
    static bool notifyRunningInstance();

    // 抢占监听；返回 false 表示监听失败（不致命，只是失去唤回能力）
    bool listen();

signals:
    void primaryChanged();
    void raisePendingChanged();

    // 另一个进程请求把主窗口唤到前台
    void raiseRequested();

private:
    explicit AppInstance(QObject *parent);
    ~AppInstance() override;

    void handleConnection();
    void requestRaise();

    QLocalServer *m_server = nullptr;
    bool m_primary = false;
    bool m_raisePending = false;
};

#endif // APPINSTANCE_H
