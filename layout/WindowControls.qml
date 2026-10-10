// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2025-2026 QueMusic Contributors
//
// 主窗口生命周期：后台播放（隐藏窗口保活）/ 托盘隐藏与恢复、关闭前保存会话与窗口几何、退出流程。
import QtQuick
import QueMusic 1.0

QtObject {
    id: root

    property Window targetWindow
    property SystemTrayManager tray

    property bool forceQuit: false
    property int restoreVisibility: 0
    property bool trayTipShown: false
    property bool backgroundTipShown: false

    signal sessionClosing()

    // 后台播放开启时，关闭按钮只隐藏窗口：进程与音频线程继续跑，音乐不中断
    function keepPlayingInBackground(): bool {
        return Config.backgroundPlay && !forceQuit
    }

    // 关闭前把「下次启动要恢复的东西」全部落盘。
    // 转入后台后进程可能再也没有关闭事件（被系统直接杀掉等），所以隐藏之前必须先存。
    function saveSession(): void {
        const q = Playback.queue
        const p = Playback.player
        const idx = q ? q.playListIndex : -1
        if (q && q.count > 0 && idx >= 0) {
            const item = q.get(idx)
            Options.lastSongs.name = Playback.musicTitle
            Options.lastSongs.artist = Playback.musicArtist
            Options.lastSongs.cover = (p && p.urlStr) || "qrc:/QueMusic/resources/app/musicpic.png"
            Options.lastSongs.hash = item.path
            Options.lastSongs.source = item.source
        }
        if (Config.rememberWindow && targetWindow
                && targetWindow.visibility !== Window.Maximized
                && targetWindow.visibility !== Window.FullScreen) {
            Config.winX = targetWindow.x
            Config.winY = targetWindow.y
            Config.winW = targetWindow.width
            Config.winH = targetWindow.height
        }
        Playback.saveQueue()
        Playback.flush()
    }

    // 关闭按钮 / Alt+F4 / 任务栏「关闭窗口」的唯一出口
    function toClosing(): void {
        saveSession()
        if (keepPlayingInBackground()) {
            hideToBackground()
            return
        }
        sessionClosing()
        if (tray)
            tray.quitApplication()
        else
            Qt.quit()
    }

    // 转入后台：有托盘就藏进托盘，没有托盘就只能藏窗口 + 提示唤回方式
    function hideToBackground(): void {
        if (tray && tray.available) {
            hideToTray()
            return
        }
        if (!backgroundTipShown) {
            // 先亮提示再隐藏：窗口一藏，就没有任何界面能告诉用户「怎么找回来」了
            backgroundTipShown = true
            Options.warned("已转入后台播放，音乐不会中断；再次启动 QueMusic 即可唤回窗口", 0)
            pendingHide.restart()
            return
        }
        hideWindow()
    }

    function hideToTray(): void {
        if (!targetWindow || !targetWindow.visible)
            return
        restoreVisibility = targetWindow.visibility
        targetWindow.hide()
        if (!trayTipShown) {
            trayTipShown = true
            if (tray)
                tray.showMessage("QueMusic", "已最小化到系统托盘，点击托盘图标可恢复",
                                 SystemTrayManager.Information)
        }
    }

    function hideWindow(): void {
        if (!targetWindow || !targetWindow.visible)
            return
        restoreVisibility = targetWindow.visibility
        targetWindow.hide()
    }

    function restoreWindow(): void {
        if (!targetWindow)
            return
        pendingHide.stop()
        if (!targetWindow.visible) {
            if (restoreVisibility === Window.Maximized)
                targetWindow.showMaximized()
            else if (restoreVisibility === Window.FullScreen)
                targetWindow.showFullScreen()
            else
                targetWindow.showNormal()
        } else if (targetWindow.visibility === Window.Minimized) {
            targetWindow.showNormal()
        }
        targetWindow.raise()
        targetWindow.requestActivate()
    }

    function quitApp(): void {
        forceQuit = true
        toClosing()
    }

    // 无托盘时先让提示停留一下再隐藏窗口（QWarn 默认 1.5s），避免用户什么都没看见就没了窗口
    property Timer pendingHide: Timer {
        interval: 1600
        onTriggered: root.hideWindow()
    }
}
