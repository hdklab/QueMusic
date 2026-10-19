// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 QueMusic Contributors
//
import QtQuick
import QtQuick.Controls.Basic
import QueMusic 1.0

GridView {
    id: view
    contentWidth: view.width - 16
    synchronousDrag: true
    reuseItems: true
    onDraggingChanged: view.scrollToY = view.contentY
    topMargin: 6
    bottomMargin: 24
    rightMargin: 16
    property int scrollToY: view.contentY
    property bool enabled: true
    // 加载态 / 空态：切平台、翻页时列表会先清空再重拉，给一个明确的等待反馈，
    // 不然用户只看到一块空白。两个属性都不设时行为与以前完全一致。
    property bool loading: false
    property string emptyText: ""
    clip: true
    signal topScroll()
    function scrollTop(): void {
        listViewAnime.stop();
        scrollToY = view.originY - view.topMargin;
        contentY = view.originY - view.topMargin;
    }

    // 加载中：转圈（放在网格之上，不占布局）
    AnimatedImage {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: view.emptyText !== "" ? -14 : 0
        width: 36
        height: 36
        source: "qrc:/QueMusic/resources/loader.gif"
        visible: view.count === 0 && view.loading
        playing: visible
    }
    // 拉完了还是空：说明没拿到内容（网络/平台接口问题），别再让用户盯着空白
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 24
        width: Math.min(implicitWidth, view.width - 48)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        visible: view.count === 0 && !view.loading && view.emptyText !== ""
        text: view.emptyText
        color: Theme.textColor
        font.pixelSize: Style.textmain
    }

    ScrollBar.vertical: ScrollBar {
        id: viewBar
        parent: view
        anchors.top: view.top
        anchors.right: view.right
        anchors.bottom: view.bottom
        onPressedChanged: {
            view.scrollToY = view.contentY
        }
    }
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        enabled: view.enabled
        readonly property real wheelHeightCount: Qt.application.styleHints.wheelScrollLines * 0.25
        readonly property int scrollBottom: view.contentHeight - view.height + view.bottomMargin + view.originY
        onWheel: (event) => {
            listViewAnime.running = false;
            view.scrollToY = Math.max(view.originY - view.topMargin, Math.min( view.scrollToY - (event.angleDelta.y * wheelHeightCount), scrollBottom));
            viewBar.active = true;
            event.accepted = true;
            listViewAnime.running = true;
            if(event.angleDelta.y > 0 && view.scrollToY === - view.topMargin) {
                view.topScroll()
            }
        }
    }
    NumberAnimation {
        id: listViewAnime
        target: view
        property: "contentY"
        duration: 240
        to: view.scrollToY
        easing.type: Easing.OutCubic
        onFinished: viewBar.active = false
    }
}
