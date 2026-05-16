//@ pragma IconTheme Papirus-Dark

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    property string configPath: Quickshell.env("CODEXBAR_CONFIG") || ((Quickshell.env("HOME") || "") + "/.codexbar/config.json")
    property string stateDir: Quickshell.env("CODEXBAR_STATE_DIR") || ((Quickshell.env("HOME") || "") + "/.local/state/codexbar")
    property string codexbarBin: Quickshell.env("CODEXBAR_BIN") || "codexbar"
    property string snapshotPath: stateDir + "/snapshot.json"
    property string uiPath: stateDir + "/ui.json"
    property string textFont: "Fira Code"
    property string iconFont: "Symbols Nerd Font Mono"
    property var glyphs: ({
        refresh: "",
        close: "",
        pin: "",
        pinned: "",
        auto: "",
        hidden: "",
        shown: "",
        overview: "",
        dashboard: "",
        provider: "",
        display: "",
        note: "",
        alert: "󰀨",
        meter: "",
        status: "",
        history: "",
        settings: "",
        bell: "",
        privacy: "",
        storage: "",
        cost: ""
    })

    property var viewData: snapshotAdapter.view && snapshotAdapter.view.summary ? snapshotAdapter.view : ({ summary: {}, chip: {}, providers: [] })
    property var providerViews: viewData.providers || []
    property string focusProviderId: ""
    property string activeView: "overview"

    function accentColor(provider) {
        return provider && provider.accent ? provider.accent : "#82FB9C"
    }

    function withAlpha(hex, alpha) {
        var value = hex
        if (value && typeof value !== "string") {
            value = value.toString()
        }

        if (!value || value.length < 7) {
            return Qt.rgba(0.5, 0.98, 0.61, alpha)
        }

        var r = parseInt(value.slice(1, 3), 16) / 255
        var g = parseInt(value.slice(3, 5), 16) / 255
        var b = parseInt(value.slice(5, 7), 16) / 255
        return Qt.rgba(r, g, b, alpha)
    }

    function statusColor(provider) {
        if (!provider) {
            return "#6A6E95"
        }
        if (provider.status === "error" || provider.status === "critical") {
            return "#E06C75"
        }
        if (provider.status === "warning") {
            return "#F2C572"
        }
        if (provider.status === "incident") {
            return "#82A7F4"
        }
        if (provider.status === "stale" || provider.status === "loading") {
            return "#6A6E95"
        }

        return accentColor(provider)
    }

    function runCodexbar(args) {
        if (actionRunner.running) {
            actionRunner.signal(9)
            actionRunner.running = false
        }

        actionRunner.command = [root.codexbarBin].concat(args).concat(["--config", root.configPath])
        actionRunner.running = true
    }

    function displayProvider() {
        var displayId = snapshotAdapter.displayProvider || ""
        var provider = findProvider(displayId)
        return provider || firstUsableProvider()
    }

    function firstUsableProvider() {
        var index

        for (index = 0; index < providerViews.length; index += 1) {
            if (providerViews[index].enabled && providerViews[index].visible) {
                return providerViews[index]
            }
        }

        return providerViews.length ? providerViews[0] : null
    }

    function findProvider(providerId) {
        var index

        for (index = 0; index < providerViews.length; index += 1) {
            if (providerViews[index].id === providerId) {
                return providerViews[index]
            }
        }

        return null
    }

    function focusProvider() {
        return findProvider(focusProviderId) || displayProvider()
    }

    function setView(viewName) {
        activeView = viewName
        if (viewName === "detail") {
            syncFocus()
        }
    }

    function providerHistory() {
        var provider = focusProvider()
        return provider && provider.historyDays ? provider.historyDays : []
    }

    function cacheCommand(target) {
        runCodexbar(["cache", "clear", target])
    }

    function compactJoin(parts) {
        var output = []
        var index
        for (index = 0; index < parts.length; index += 1) {
            if (parts[index]) {
                output.push(parts[index])
            }
        }
        return output.join("  /  ")
    }

    function overviewProviders() {
        var providers = []
        var index

        for (index = 0; index < providerViews.length; index += 1) {
            if (providerViews[index].enabled && providerViews[index].visible && providerViews[index].inOverview) {
                providers.push(providerViews[index])
            }
        }

        return providers
    }

    function fallbackFocusId() {
        if (uiAdapter.focusProvider && findProvider(uiAdapter.focusProvider)) {
            return uiAdapter.focusProvider
        }

        var display = displayProvider()
        if (display) {
            return display.id
        }

        return providerViews.length ? providerViews[0].id : ""
    }

    function syncFocus() {
        if (!providerViews.length) {
            focusProviderId = ""
            return
        }

        focusProviderId = fallbackFocusId()
        if (uiAdapter.open && focusProviderId && uiAdapter.focusProvider !== focusProviderId) {
            uiAdapter.focusProvider = focusProviderId
        }
    }

    function setFocus(providerId) {
        if (!providerId) {
            syncFocus()
            return
        }

        focusProviderId = providerId
        if (uiAdapter.focusProvider !== providerId) {
            uiAdapter.focusProvider = providerId
        }
    }

    function closePanel() {
        uiAdapter.open = false
    }

    function providerCommand(action, providerId) {
        runCodexbar(["providers", action, providerId])
    }

    function overviewCommand(action, providerId) {
        runCodexbar(["providers", "overview", action, providerId])
    }

    function displayCommand(action, value) {
        var args = ["display", action]
        if (value) {
            args.push(value)
        }
        runCodexbar(args)
    }

    function runtimeCommand(mode, seconds) {
        var args = ["runtime", "cadence", mode]
        if (seconds) {
            args.push(seconds)
        }
        runCodexbar(args)
    }

    function notificationCommand(enabled) {
        runCodexbar(["notifications", enabled ? "enable" : "disable"])
    }

    function privacyCommand(hidden) {
        runCodexbar(["privacy", hidden ? "hide" : "show"])
    }

    Process {
        id: actionRunner
        running: false
        stdout: StdioCollector {}
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length) {
                    console.log(text.trim())
                }
            }
        }
    }

    FileView {
        id: snapshotFile
        path: root.snapshotPath
        watchChanges: true
        onFileChanged: reload()

        JsonAdapter {
            id: snapshotAdapter
            property string generatedAt: ""
            property var enabledProviders: []
            property var visibleProviders: []
            property var hiddenProviders: []
            property var overviewProviders: []
            property var autoSelectableProviders: []
            property string selectedProvider: ""
            property string displayProvider: ""
            property var results: ({})
            property var view: ({})
        }
    }

    FileView {
        id: uiFile
        path: root.uiPath
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: uiAdapter
            property bool open: false
            property string focusProvider: ""
            property string requestedAt: ""

            onOpenChanged: {
                if (open) {
                    root.syncFocus()
                }
            }

            onFocusProviderChanged: root.syncFocus()
        }
    }

    Component.onCompleted: {
        snapshotFile.reload()
        uiFile.reload()
    }

    component CodexButton: Button {
        id: control
        property color accent: "#82FB9C"
        property string glyph: ""
        property bool compact: false

        font.family: root.textFont
        font.pixelSize: compact ? 10 : 11
        hoverEnabled: true
        padding: 0
        implicitHeight: compact ? 26 : 30
        implicitWidth: Math.max(compact ? 74 : 92, contentItem.implicitWidth + 18)

        background: Rectangle {
            radius: 9
            color: control.down ? withAlpha(control.accent, 0.26) : (control.hovered ? withAlpha(control.accent, 0.18) : withAlpha(control.accent, 0.10))
            border.color: control.hovered ? withAlpha(control.accent, 0.60) : withAlpha(control.accent, 0.34)
            border.width: 1
        }

        contentItem: Label {
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: control.glyph ? (control.glyph + (control.text ? "  " + control.text : "")) : control.text
            color: "#DDF7FF"
            font: control.font
        }
    }

    component ViewTab: Button {
        id: tab
        property string view: ""
        property string glyph: ""
        property color accent: "#82FB9C"
        property bool selected: root.activeView === view

        font.family: root.textFont
        font.pixelSize: 11
        font.bold: selected
        hoverEnabled: true
        padding: 0
        implicitHeight: 32
        implicitWidth: Math.max(120, contentItem.implicitWidth + 24)
        onClicked: root.setView(view)

        background: Rectangle {
            radius: 10
            color: tab.selected ? withAlpha(tab.accent, 0.24) : (tab.hovered ? withAlpha(tab.accent, 0.14) : "#0E1423")
            border.width: 1
            border.color: tab.selected ? withAlpha(tab.accent, 0.70) : withAlpha(tab.accent, 0.24)
        }

        contentItem: Label {
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: tab.glyph ? (tab.glyph + "  " + tab.text) : tab.text
            color: tab.selected ? "#F6FBFF" : "#A8B3D7"
            font: tab.font
            elide: Text.ElideRight
        }
    }

    component BadgePill: Rectangle {
        id: pill
        property string text: ""
        property string icon: ""
        property color accent: "#6A6E95"
        property color foreground: "#DDF7FF"
        property int minimumWidth: 0

        radius: 8
        implicitHeight: 20
        implicitWidth: Math.max(minimumWidth, contentRow.implicitWidth + 14)
        color: withAlpha(accent, 0.14)
        border.width: 1
        border.color: withAlpha(accent, 0.34)

        RowLayout {
            id: contentRow
            anchors.centerIn: parent
            spacing: 4

            Text {
                visible: pill.icon.length > 0
                text: pill.icon
                color: pill.foreground
                font.family: root.iconFont
                font.pixelSize: 10
                renderType: Text.NativeRendering
            }

            Label {
                text: pill.text
                color: pill.foreground
                font.family: root.textFont
                font.pixelSize: 10
                font.bold: true
            }
        }
    }

    component SectionHeader: RowLayout {
        id: sectionHeader
        property string text: ""
        property string icon: ""
        property color accent: "#8E97B5"

        spacing: 6

        Text {
            text: sectionHeader.icon
            color: sectionHeader.accent
            font.family: root.iconFont
            font.pixelSize: 12
            visible: text.length > 0
        }

        Label {
            text: sectionHeader.text
            color: sectionHeader.accent
            font.family: root.textFont
            font.pixelSize: 10
            font.bold: true
        }
    }

    component MetricBar: Item {
        id: metricBar
        property real usedPercent: 0
        property color accent: "#82FB9C"

        implicitHeight: 6
        implicitWidth: 220

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: "#131827"
            border.width: 1
            border.color: withAlpha(metricBar.accent, 0.18)
        }

        Rectangle {
            width: Math.max(0, Math.min(metricBar.width, metricBar.width * (metricBar.usedPercent / 100.0)))
            height: metricBar.height
            radius: height / 2
            color: metricBar.accent
            opacity: 0.92
        }
    }

    component CardFrame: Rectangle {
        id: card
        property color accent: "#82FB9C"
        radius: 16
        color: "#101527"
        border.width: 1
        border.color: withAlpha(accent, 0.28)
    }

    component HistoryDayTile: CardFrame {
        id: dayTile
        property var itemData: ({})
        Layout.fillWidth: true
        Layout.preferredHeight: 86
        accent: focusProvider() ? statusColor(focusProvider()) : "#82FB9C"
        color: "#0E1423"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Label {
                    Layout.fillWidth: true
                    text: itemData.label || itemData.date || "--"
                    color: "#F6FBFF"
                    font.family: root.textFont
                    font.pixelSize: 11
                    font.bold: true
                }

                Label {
                    text: itemData.quotaText || "No quota"
                    color: dayTile.accent
                    font.family: root.textFont
                    font.pixelSize: 10
                    font.bold: true
                }
            }

            MetricBar {
                Layout.fillWidth: true
                usedPercent: itemData.barPercent || 0
                accent: dayTile.accent
            }

            Label {
                Layout.fillWidth: true
                text: itemData.detail || "No local token summary"
                color: "#8E97B5"
                font.family: root.textFont
                font.pixelSize: 10
                elide: Text.ElideRight
            }
        }
    }

    component ProviderIconBubble: Rectangle {
        id: bubble
        property string icon: ""
        property color accent: "#82FB9C"

        width: 28
        height: 28
        radius: 10
        color: withAlpha(accent, 0.16)
        border.width: 1
        border.color: withAlpha(accent, 0.34)

        Text {
            anchors.centerIn: parent
            text: bubble.icon
            color: bubble.accent
            font.family: root.iconFont
            font.pixelSize: 15
        }
    }

    component DetailTile: CardFrame {
        id: tile
        property var itemData: ({})
        Layout.fillWidth: true
        Layout.preferredHeight: 72
        accent: focusProvider() ? statusColor(focusProvider()) : "#82FB9C"
        color: "#0E1423"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: itemData.icon || ""
                    color: tile.accent
                    font.family: root.iconFont
                    font.pixelSize: 13
                }

                Label {
                    Layout.fillWidth: true
                    text: itemData.label || ""
                    color: "#AEB8D9"
                    font.family: root.textFont
                    font.pixelSize: 10
                    font.bold: true
                }
            }

            Label {
                Layout.fillWidth: true
                text: itemData.value || "--"
                color: "#F6FBFF"
                font.family: root.textFont
                font.pixelSize: 15
                font.bold: true
                elide: Text.ElideRight
            }

            Label {
                Layout.fillWidth: true
                text: itemData.detail || ""
                color: "#7F89A8"
                font.family: root.textFont
                font.pixelSize: 10
                elide: Text.ElideRight
                visible: !!itemData.detail
            }
        }
    }

    component ProviderRow: CardFrame {
        id: providerRow
        property var providerData: ({})
        implicitHeight: 78
        accent: statusColor(providerData)
        color: providerData.id === root.focusProviderId ? "#141C31" : "#0E1423"

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.setFocus(providerRow.providerData.id)
                root.setView("detail")
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 11
            spacing: 10

            ProviderIconBubble {
                icon: providerRow.providerData.icon || ""
                accent: statusColor(providerRow.providerData)
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                RowLayout {
                    Layout.fillWidth: true
                    Layout.minimumHeight: 20

                    Label {
                        text: providerRow.providerData.label
                        color: "#F6FBFF"
                        font.family: root.textFont
                        font.pixelSize: 12
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true }

                    BadgePill {
                        visible: providerRow.providerData.display
                        text: "display"
                        icon: root.glyphs.display
                        accent: statusColor(providerRow.providerData)
                    }
                }

                Label {
                    Layout.fillWidth: true
                    text: providerRow.providerData.chipText || "--"
                    color: statusColor(providerRow.providerData)
                    font.family: root.textFont
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        BadgePill {
                            text: providerRow.providerData.enabled ? "active" : "off"
                            icon: providerRow.providerData.enabled ? root.glyphs.status : root.glyphs.close
                            accent: providerRow.providerData.enabled ? "#82FB9C" : "#6A6E95"
                            minimumWidth: 68
                        }

                        BadgePill {
                            text: providerRow.providerData.visible ? "shown" : "hidden"
                            icon: providerRow.providerData.visible ? root.glyphs.shown : root.glyphs.hidden
                            accent: providerRow.providerData.visible ? "#82A7F4" : "#6A6E95"
                            minimumWidth: 72
                        }
                    }
                }
            }
        }

    onProviderViewsChanged: {
        if (!findProvider(focusProviderId)) {
            syncFocus()
        }
    }

    PanelWindow {
        id: panelWindow
        visible: uiAdapter.open
        screen: Quickshell.screens.length ? Quickshell.screens[0] : null
        color: "#090D18"
        focusable: true
        implicitWidth: 1080
        implicitHeight: 760

        anchors {
            top: true
            right: true
        }

        margins {
            top: 44
            right: 18
        }

        onVisibleChanged: {
            if (visible) {
                root.syncFocus()
            }
        }

        FocusScope {
            anchors.fill: parent
            focus: true

            Keys.onEscapePressed: root.closePanel()

            CardFrame {
                anchors.fill: parent
                anchors.margins: 10
                accent: focusProvider() ? statusColor(focusProvider()) : "#82FB9C"
                color: "#0B0F1E"

                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#12182B" }
                        GradientStop { position: 1.0; color: "#090D18" }
                    }
                    opacity: 1.0
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 12

                    CardFrame {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 78
                        accent: focusProvider() ? statusColor(focusProvider()) : "#82FB9C"

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 12

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                RowLayout {
                                    spacing: 8

                                    ProviderIconBubble {
                                        icon: focusProvider() ? focusProvider().icon : root.glyphs.provider
                                        accent: focusProvider() ? statusColor(focusProvider()) : "#82FB9C"
                                    }

                                    ColumnLayout {
                                        spacing: 2

                                        Label {
                                            text: viewData.summary && viewData.summary.displayLabel ? ("CodexBar / " + viewData.summary.displayLabel) : "CodexBar"
                                            color: "#F6FBFF"
                                            font.family: root.textFont
                                            font.pixelSize: 18
                                            font.bold: true
                                        }

                                        Label {
                                            text: viewData.summary && viewData.summary.displayText ? viewData.summary.displayText : "Waiting for provider cache"
                                            color: focusProvider() ? statusColor(focusProvider()) : "#DDF7FF"
                                            font.family: root.textFont
                                            font.pixelSize: 12
                                        }
                                    }
                                }

                                Label {
                                    text: (viewData.summary.updatedText || "Waiting for cached data") + "  •  " + (viewData.summary.activeCount || 0) + " active  •  " + (viewData.summary.visibleCount || 0) + " visible"
                                    color: "#8E97B5"
                                    font.family: root.textFont
                                    font.pixelSize: 10
                                }
                            }

                            RowLayout {
                                spacing: 6

                                BadgePill {
                                    text: viewData.summary.modeLabel || "Highest usage"
                                    icon: root.glyphs.status
                                    accent: "#82FB9C"
                                }

                                BadgePill {
                                    text: viewData.summary.showUsedLabel || "Remaining"
                                    icon: root.glyphs.meter
                                    accent: "#82A7F4"
                                }

                                BadgePill {
                                    text: viewData.summary.metricModeLabel || "both"
                                    icon: root.glyphs.overview
                                    accent: "#F2C572"
                                }

                                BadgePill {
                                    text: viewData.summary.refreshModeLabel || "120s refresh"
                                    icon: root.glyphs.refresh
                                    accent: "#82FB9C"
                                }

                                BadgePill {
                                    text: viewData.summary.notificationsLabel || "Notify off"
                                    icon: root.glyphs.bell
                                    accent: viewData.summary.notificationsLabel === "Notify on" ? "#82A7F4" : "#6A6E95"
                                }

                                CodexButton {
                                    text: "Refresh"
                                    glyph: root.glyphs.refresh
                                    accent: "#82FB9C"
                                    compact: true
                                    onClicked: root.runCodexbar(["refresh"])
                                }

                                CodexButton {
                                    text: "Close"
                                    glyph: root.glyphs.close
                                    accent: "#E06C75"
                                    compact: true
                                    onClicked: root.closePanel()
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        ViewTab {
                            text: "Overview"
                            view: "overview"
                            glyph: root.glyphs.overview
                            accent: "#82FB9C"
                        }

                        ViewTab {
                            text: "Provider Detail"
                            view: "detail"
                            glyph: root.glyphs.provider
                            accent: focusProvider() ? statusColor(focusProvider()) : "#82A7F4"
                        }

                        ViewTab {
                            text: "History"
                            view: "history"
                            glyph: root.glyphs.history
                            accent: "#F2C572"
                        }

                        ViewTab {
                            text: "Settings"
                            view: "settings"
                            glyph: root.glyphs.settings
                            accent: "#C4D2ED"
                        }

                        Item { Layout.fillWidth: true }

                        BadgePill {
                            text: focusProvider() ? focusProvider().status : "loading"
                            icon: root.glyphs.status
                            accent: focusProvider() ? statusColor(focusProvider()) : "#6A6E95"
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.activeView === "overview" || root.activeView === "detail"
                        spacing: 12

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 12

                            CardFrame {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: root.activeView === "overview"
                                accent: focusProvider() ? statusColor(focusProvider()) : "#82FB9C"

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 10

                                    RowLayout {
                                        spacing: 8

                                        Text {
                                            text: root.glyphs.overview
                                            color: "#82A7F4"
                                            font.family: root.iconFont
                                            font.pixelSize: 13
                                        }

                                        Label {
                                            text: "Overview"
                                            color: "#F6FBFF"
                                            font.family: root.textFont
                                            font.pixelSize: 12
                                            font.bold: true
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        BadgePill {
                                            text: viewData.summary.updatedText || "Waiting for cached data"
                                            icon: root.glyphs.refresh
                                            accent: viewData.summary.stale ? "#F2C572" : "#82FB9C"
                                        }

                                        BadgePill {
                                            text: (viewData.summary.activeCount || 0) + " active"
                                            icon: root.glyphs.status
                                            accent: "#82FB9C"
                                        }

                                        BadgePill {
                                            text: viewData.summary.statusLabel || "Status off"
                                            icon: root.glyphs.status
                                            accent: viewData.summary.statusLabel === "Status on" ? "#82A7F4" : "#6A6E95"
                                        }

                                        BadgePill {
                                            text: viewData.summary.refreshModeLabel || "120s refresh"
                                            icon: root.glyphs.refresh
                                            accent: "#F2C572"
                                        }

                                        BadgePill {
                                            text: viewData.summary.privacyLabel || "Privacy off"
                                            icon: root.glyphs.privacy
                                            accent: viewData.summary.privacyLabel === "Privacy on" ? "#F2C572" : "#6A6E95"
                                        }

                                        Item { Layout.fillWidth: true }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Repeater {
                                            model: providerViews

                                            delegate: CardFrame {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 118
                                                accent: statusColor(modelData)
                                                color: modelData.id === root.focusProviderId ? "#141C31" : "#0E1423"

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        root.setFocus(modelData.id)
                                                        root.setView("detail")
                                                    }
                                                }

                                                ColumnLayout {
                                                    anchors.fill: parent
                                                    anchors.margins: 10
                                                    spacing: 4

                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        Layout.minimumHeight: 20
                                                        spacing: 8

                                                        ProviderIconBubble {
                                                            icon: modelData.icon || ""
                                                            accent: statusColor(modelData)
                                                        }

                                                        ColumnLayout {
                                                            Layout.fillWidth: true
                                                            spacing: 2

                                                            Label {
                                                                text: modelData.label
                                                                color: "#F6FBFF"
                                                                font.family: root.textFont
                                                                font.pixelSize: 11
                                                                font.bold: true
                                                            }

                                                            Label {
                                                                text: modelData.chipText || "--"
                                                                color: statusColor(modelData)
                                                                font.family: root.textFont
                                                                font.pixelSize: 11
                                                                font.bold: true
                                                            }
                                                        }

                                                        Item { Layout.fillWidth: true }

                                                        BadgePill {
                                                            visible: modelData.display
                                                            text: "display"
                                                            icon: root.glyphs.display
                                                            accent: statusColor(modelData)
                                                        }
                                                    }

                                                    MetricBar {
                                                        Layout.fillWidth: true
                                                        usedPercent: modelData.dominantMetric ? modelData.dominantMetric.usedPercent : 0
                                                        accent: statusColor(modelData)
                                                        visible: !!modelData.dominantMetric
                                                    }

                                                    Label {
                                                        Layout.fillWidth: true
                                                        text: modelData.serviceStatusText || "Status unknown"
                                                        color: statusColor(modelData)
                                                        font.family: root.textFont
                                                        font.pixelSize: 10
                                                        elide: Text.ElideRight
                                                    }

                                                    Label {
                                                        Layout.fillWidth: true
                                                        text: modelData.localUsageText || "Local usage pending"
                                                        color: "#8E97B5"
                                                        font.family: root.textFont
                                                        font.pixelSize: 10
                                                        elide: Text.ElideRight
                                                    }

                                                    Label {
                                                        Layout.fillWidth: true
                                                        text: modelData.freshnessText || "Waiting for cached data"
                                                        color: "#8E97B5"
                                                        font.family: root.textFont
                                                        font.pixelSize: 10
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Item { Layout.fillHeight: true }

                                    CardFrame {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 96
                                        accent: focusProvider() ? statusColor(focusProvider()) : "#82FB9C"
                                        color: "#0E1423"

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 12

                                            ProviderIconBubble {
                                                icon: displayProvider() ? displayProvider().icon : root.glyphs.provider
                                                accent: displayProvider() ? statusColor(displayProvider()) : "#82FB9C"
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 4

                                                Label {
                                                    text: displayProvider() ? ("Active display: " + displayProvider().label) : "Active display pending"
                                                    color: "#F6FBFF"
                                                    font.family: root.textFont
                                                    font.pixelSize: 15
                                                    font.bold: true
                                                }

                                                Label {
                                                    Layout.fillWidth: true
                                                    text: displayProvider() ? root.compactJoin([displayProvider().chipText, displayProvider().serviceStatusText, displayProvider().historySummary]) : "Waiting for cached data"
                                                    color: "#A8B3D7"
                                                    font.family: root.textFont
                                                    font.pixelSize: 11
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            CodexButton {
                                                text: "Refresh"
                                                glyph: root.glyphs.refresh
                                                accent: "#82FB9C"
                                                compact: true
                                                onClicked: root.runCodexbar(["refresh"])
                                            }
                                        }
                                    }
                                }
                            }

                            CardFrame {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: root.activeView === "detail"
                                accent: focusProvider() ? statusColor(focusProvider()) : "#82FB9C"

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    spacing: 12

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 10

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 4

                                                RowLayout {
                                                    spacing: 8

                                                    ProviderIconBubble {
                                                        icon: focusProvider() ? focusProvider().icon : ""
                                                        accent: focusProvider() ? statusColor(focusProvider()) : "#82FB9C"
                                                    }

                                                    ColumnLayout {
                                                        spacing: 2

                                                        Label {
                                                            text: focusProvider() ? focusProvider().label : "No provider selected"
                                                            color: "#F6FBFF"
                                                            font.family: root.textFont
                                                            font.pixelSize: 18
                                                            font.bold: true
                                                        }

                                                        Label {
                                                            text: focusProvider() ? focusProvider().identityText : "Waiting for provider data"
                                                            color: "#9FA8C6"
                                                            font.family: root.textFont
                                                            font.pixelSize: 11
                                                        }

                                                        Label {
                                                            text: focusProvider() ? ((focusProvider().serviceStatusText || "Status unknown") + (focusProvider().localUsageText ? ("  •  " + focusProvider().localUsageText) : "")) : ""
                                                            color: focusProvider() ? statusColor(focusProvider()) : "#8E97B5"
                                                            font.family: root.textFont
                                                            font.pixelSize: 10
                                                            elide: Text.ElideRight
                                                        }
                                                    }
                                                }
                                            }

                                            Repeater {
                                                model: focusProvider() ? focusProvider().badges : []

                                                delegate: BadgePill {
                                                    required property string modelData
                                                    text: modelData
                                                    icon: modelData === "display" ? root.glyphs.display : (modelData === "pinned" ? root.glyphs.pinned : (modelData === "hidden" ? root.glyphs.hidden : (modelData === "overview" ? root.glyphs.overview : "")))
                                                    accent: statusColor(focusProvider())
                                                }
                                            }
                                        }

                                        CardFrame {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 132
                                            accent: focusProvider() ? statusColor(focusProvider()) : "#82FB9C"
                                            color: "#111829"

                                            ColumnLayout {
                                                anchors.fill: parent
                                                anchors.margins: 14
                                                spacing: 8

                                                RowLayout {
                                                    spacing: 8

                                                    Text {
                                                        text: focusProvider() && focusProvider().hero ? focusProvider().hero.icon : ""
                                                        color: focusProvider() ? statusColor(focusProvider()) : "#82FB9C"
                                                        font.family: root.iconFont
                                                        font.pixelSize: 13
                                                    }

                                                    Label {
                                                        text: focusProvider() && focusProvider().hero ? focusProvider().hero.title : "Status"
                                                        color: "#A8B3D7"
                                                        font.family: root.textFont
                                                        font.pixelSize: 11
                                                        font.bold: true
                                                    }
                                                }

                                                RowLayout {
                                                    Layout.fillWidth: true

                                                    Label {
                                                        text: focusProvider() && focusProvider().hero ? focusProvider().hero.value : (focusProvider() ? focusProvider().chipText : "--")
                                                        color: focusProvider() ? statusColor(focusProvider()) : "#DDF7FF"
                                                        font.family: root.textFont
                                                        font.pixelSize: 24
                                                        font.bold: true
                                                    }

                                                    Item { Layout.fillWidth: true }

                                                    BadgePill {
                                                        visible: !!(focusProvider() && focusProvider().hero && focusProvider().hero.supporting)
                                                        text: focusProvider() && focusProvider().hero ? focusProvider().hero.supporting : ""
                                                        accent: focusProvider() ? statusColor(focusProvider()) : "#82FB9C"
                                                    }
                                                }

                                                MetricBar {
                                                    Layout.fillWidth: true
                                                    visible: !!(focusProvider() && focusProvider().hero && focusProvider().hero.progressVisible)
                                                    usedPercent: focusProvider() && focusProvider().hero ? focusProvider().hero.progressPercent : 0
                                                    accent: focusProvider() ? statusColor(focusProvider()) : "#82FB9C"
                                                }

                                                Label {
                                                    text: focusProvider() && focusProvider().hero && focusProvider().hero.detail ? focusProvider().hero.detail : "No additional quota detail"
                                                    color: "#9FA8C6"
                                                    font.family: root.textFont
                                                    font.pixelSize: 10
                                                    wrapMode: Text.Wrap
                                                    Layout.fillWidth: true
                                                }
                                            }
                                        }

                                        GridLayout {
                                            Layout.fillWidth: true
                                            columns: 2
                                            rowSpacing: 8
                                            columnSpacing: 8

                                            Repeater {
                                                model: focusProvider() ? focusProvider().detailCards : []

                                                delegate: DetailTile {
                                                    required property var modelData
                                                    itemData: modelData
                                                }
                                            }
                                        }

                                        CardFrame {
                                            visible: !!(focusProvider() && (focusProvider().error || focusProvider().notes.length || focusProvider().incident))
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: notesColumn.implicitHeight + 24
                                            accent: focusProvider() ? statusColor(focusProvider()) : "#E06C75"
                                            color: "#17111A"

                                            ColumnLayout {
                                                id: notesColumn
                                                anchors.fill: parent
                                                anchors.margins: 12
                                                spacing: 6

                                                RowLayout {
                                                    spacing: 8

                                                    Text {
                                                        text: root.glyphs.alert
                                                        color: focusProvider() ? statusColor(focusProvider()) : "#E06C75"
                                                        font.family: root.iconFont
                                                        font.pixelSize: 13
                                                    }

                                                    Label {
                                                        text: "Provider notes"
                                                        color: "#F6FBFF"
                                                        font.family: root.textFont
                                                        font.pixelSize: 11
                                                        font.bold: true
                                                    }
                                                }

                                                Label {
                                                    visible: !!(focusProvider() && focusProvider().error)
                                                    text: focusProvider() ? focusProvider().error : ""
                                                    color: "#F6B7BF"
                                                    font.family: root.textFont
                                                    font.pixelSize: 11
                                                    wrapMode: Text.Wrap
                                                    Layout.fillWidth: true
                                                }

                                                Label {
                                                    visible: !!(focusProvider() && focusProvider().incident)
                                                    text: focusProvider() ? focusProvider().incident : ""
                                                    color: "#BFD2FF"
                                                    font.family: root.textFont
                                                    font.pixelSize: 11
                                                    wrapMode: Text.Wrap
                                                    Layout.fillWidth: true
                                                }

                                                Repeater {
                                                    model: focusProvider() ? focusProvider().notes : []

                                                    delegate: Label {
                                                        required property string modelData
                                                        text: root.glyphs.note + "  " + modelData
                                                        color: "#DDF7FF"
                                                        font.family: root.textFont
                                                        font.pixelSize: 10
                                                        wrapMode: Text.Wrap
                                                        Layout.fillWidth: true
                                                    }
                                                }
                                            }
                                        }

                                        Label {
                                            text: focusProvider() ? ("Source " + focusProvider().source + "  •  " + focusProvider().freshnessText) : ""
                                            color: "#8E97B5"
                                            font.family: root.textFont
                                            font.pixelSize: 10
                                        }
                                }
                            }
                        }

                        CardFrame {
                            Layout.preferredWidth: 260
                            Layout.fillHeight: true
                            accent: focusProvider() ? statusColor(focusProvider()) : "#82FB9C"

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 12

                                Label {
                                    text: root.glyphs.provider + " Providers"
                                    color: "#F6FBFF"
                                    font.family: root.textFont
                                    font.pixelSize: 12
                                    font.bold: true
                                }

                                Column {
                                    id: providerList
                                    Layout.fillWidth: true
                                    spacing: 10

                                    Repeater {
                                        model: providerViews

                                        delegate: ProviderRow {
                                            width: providerList.width
                                            providerData: modelData
                                        }
                                    }
                                }

                                Item {
                                    Layout.fillHeight: true
                                }
                            }
                        }
                    }

                    CardFrame {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.activeView === "history"
                        accent: focusProvider() ? statusColor(focusProvider()) : "#F2C572"

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 12

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                ProviderIconBubble {
                                    icon: focusProvider() ? focusProvider().icon : root.glyphs.history
                                    accent: focusProvider() ? statusColor(focusProvider()) : "#F2C572"
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3

                                    Label {
                                        text: focusProvider() ? (focusProvider().label + " history") : "History"
                                        color: "#F6FBFF"
                                        font.family: root.textFont
                                        font.pixelSize: 18
                                        font.bold: true
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: focusProvider() ? (focusProvider().historySummary || "No retained history") : "Waiting for provider data"
                                        color: "#A8B3D7"
                                        font.family: root.textFont
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                }

                                Repeater {
                                    model: providerViews

                                    delegate: CodexButton {
                                        required property var modelData
                                        text: modelData.shortLabel
                                        glyph: modelData.icon
                                        accent: modelData.id === root.focusProviderId ? statusColor(modelData) : "#6A6E95"
                                        compact: true
                                        onClicked: root.setFocus(modelData.id)
                                    }
                                }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                columns: 4
                                columnSpacing: 10
                                rowSpacing: 10
                                visible: root.providerHistory().length > 0

                                Repeater {
                                    model: root.providerHistory()

                                    delegate: HistoryDayTile {
                                        required property var modelData
                                        itemData: modelData
                                    }
                                }
                            }

                            CardFrame {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: root.providerHistory().length === 0
                                accent: "#6A6E95"
                                color: "#0E1423"

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 10

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: root.glyphs.history
                                        color: "#6A6E95"
                                        font.family: root.iconFont
                                        font.pixelSize: 30
                                    }

                                    Label {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: "No retained history yet"
                                        color: "#F6FBFF"
                                        font.family: root.textFont
                                        font.pixelSize: 16
                                        font.bold: true
                                    }

                                    Label {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: "History appears after the daemon writes daily quota or local usage snapshots."
                                        color: "#8E97B5"
                                        font.family: root.textFont
                                        font.pixelSize: 11
                                    }
                                }
                            }
                        }
                    }

                    CardFrame {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.activeView === "settings"
                        accent: "#C4D2ED"

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 14

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                ProviderIconBubble {
                                    icon: root.glyphs.settings
                                    accent: "#C4D2ED"
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3

                                    Label {
                                        text: "Settings"
                                        color: "#F6FBFF"
                                        font.family: root.textFont
                                        font.pixelSize: 18
                                        font.bold: true
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: root.compactJoin([viewData.summary.refreshModeLabel, viewData.summary.notificationsLabel, viewData.summary.privacyLabel])
                                        color: "#A8B3D7"
                                        font.family: root.textFont
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            SectionHeader {
                                text: "Runtime Cadence"
                                icon: root.glyphs.refresh
                                accent: "#8E97B5"
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 6
                                columnSpacing: 8
                                rowSpacing: 8

                                CodexButton { Layout.fillWidth: true; text: "Manual"; glyph: root.glyphs.pin; accent: viewData.summary.refreshModeLabel === "Manual refresh" ? "#82FB9C" : "#6A6E95"; compact: true; onClicked: root.runtimeCommand("manual") }
                                CodexButton { Layout.fillWidth: true; text: "1m"; accent: viewData.summary.refreshModeLabel === "60s refresh" ? "#82FB9C" : "#6A6E95"; compact: true; onClicked: root.runtimeCommand("interval", "60") }
                                CodexButton { Layout.fillWidth: true; text: "2m"; accent: viewData.summary.refreshModeLabel === "120s refresh" ? "#82FB9C" : "#6A6E95"; compact: true; onClicked: root.runtimeCommand("interval", "120") }
                                CodexButton { Layout.fillWidth: true; text: "5m"; accent: viewData.summary.refreshModeLabel === "300s refresh" ? "#82FB9C" : "#6A6E95"; compact: true; onClicked: root.runtimeCommand("interval", "300") }
                                CodexButton { Layout.fillWidth: true; text: "15m"; accent: viewData.summary.refreshModeLabel === "900s refresh" ? "#82FB9C" : "#6A6E95"; compact: true; onClicked: root.runtimeCommand("interval", "900") }
                                CodexButton { Layout.fillWidth: true; text: "30m"; accent: viewData.summary.refreshModeLabel === "1800s refresh" ? "#82FB9C" : "#6A6E95"; compact: true; onClicked: root.runtimeCommand("interval", "1800") }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    SectionHeader { text: "Display"; icon: root.glyphs.meter; accent: "#8E97B5" }

                                    GridLayout {
                                        Layout.fillWidth: true
                                        columns: 5
                                        columnSpacing: 8
                                        rowSpacing: 8

                                        CodexButton { Layout.fillWidth: true; text: "Remaining"; accent: viewData.summary.showUsedLabel === "Remaining" ? "#82FB9C" : "#6A6E95"; compact: true; onClicked: root.displayCommand("remaining") }
                                        CodexButton { Layout.fillWidth: true; text: "Used"; accent: viewData.summary.showUsedLabel === "Used" ? "#82A7F4" : "#6A6E95"; compact: true; onClicked: root.displayCommand("used") }
                                        CodexButton { Layout.fillWidth: true; text: "Both"; accent: viewData.summary.metricModeLabel === "both" ? "#82FB9C" : "#6A6E95"; compact: true; onClicked: root.displayCommand("mode", "both") }
                                        CodexButton { Layout.fillWidth: true; text: "Percent"; accent: viewData.summary.metricModeLabel === "percent" ? "#82FB9C" : "#6A6E95"; compact: true; onClicked: root.displayCommand("mode", "percent") }
                                        CodexButton { Layout.fillWidth: true; text: "Pace"; accent: viewData.summary.metricModeLabel === "pace" ? "#82FB9C" : "#6A6E95"; compact: true; onClicked: root.displayCommand("mode", "pace") }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    SectionHeader { text: "Privacy And Notifications"; icon: root.glyphs.bell; accent: "#8E97B5" }

                                    GridLayout {
                                        Layout.fillWidth: true
                                        columns: 3
                                        columnSpacing: 8
                                        rowSpacing: 8

                                        CodexButton { Layout.fillWidth: true; text: viewData.summary.notificationsLabel === "Notify on" ? "Notify Off" : "Notify On"; glyph: root.glyphs.bell; accent: viewData.summary.notificationsLabel === "Notify on" ? "#82A7F4" : "#6A6E95"; compact: true; onClicked: root.notificationCommand(viewData.summary.notificationsLabel !== "Notify on") }
                                        CodexButton { Layout.fillWidth: true; text: viewData.summary.privacyLabel === "Privacy on" ? "Show ID" : "Hide ID"; glyph: root.glyphs.privacy; accent: viewData.summary.privacyLabel === "Privacy on" ? "#F2C572" : "#6A6E95"; compact: true; onClicked: root.privacyCommand(viewData.summary.privacyLabel !== "Privacy on") }
                                        CodexButton { Layout.fillWidth: true; text: "Status"; glyph: root.glyphs.status; accent: "#82A7F4"; compact: true; onClicked: root.runCodexbar(["status"]) }
                                    }
                                }
                            }

                            SectionHeader {
                                text: "Local Scans"
                                icon: root.glyphs.cost
                                accent: "#8E97B5"
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 3
                                columnSpacing: 8
                                rowSpacing: 8

                                CodexButton { Layout.fillWidth: true; text: "Usage Scan"; glyph: root.glyphs.cost; accent: "#F2C572"; compact: true; onClicked: root.runCodexbar(["cost"]) }
                                CodexButton { Layout.fillWidth: true; text: "Storage Scan"; glyph: root.glyphs.storage; accent: "#82A7F4"; compact: true; onClicked: root.runCodexbar(["storage"]) }
                                CodexButton { Layout.fillWidth: true; text: "Refresh Now"; glyph: root.glyphs.refresh; accent: "#82FB9C"; compact: true; onClicked: root.runCodexbar(["refresh"]) }
                            }

                            SectionHeader {
                                text: "Clear Cache"
                                icon: root.glyphs.close
                                accent: "#8E97B5"
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 5
                                columnSpacing: 8
                                rowSpacing: 8

                                CodexButton { Layout.fillWidth: true; text: "Status"; accent: "#82A7F4"; compact: true; onClicked: root.cacheCommand("status") }
                                CodexButton { Layout.fillWidth: true; text: "History"; accent: "#F2C572"; compact: true; onClicked: root.cacheCommand("history") }
                                CodexButton { Layout.fillWidth: true; text: "Usage"; accent: "#F2C572"; compact: true; onClicked: root.cacheCommand("cost") }
                                CodexButton { Layout.fillWidth: true; text: "Storage"; accent: "#82A7F4"; compact: true; onClicked: root.cacheCommand("storage") }
                                CodexButton { Layout.fillWidth: true; text: "All"; accent: "#E06C75"; compact: true; onClicked: root.cacheCommand("all") }
                            }

                            Item { Layout.fillHeight: true }
                        }
                    }

                    CardFrame {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 230
                        visible: root.activeView === "detail"
                        accent: focusProvider() ? statusColor(focusProvider()) : "#82FB9C"

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    SectionHeader {
                                        text: "Focus"
                                        icon: root.glyphs.pin
                                        accent: "#8E97B5"
                                    }

                                    GridLayout {
                                        Layout.fillWidth: true
                                        columns: 3
                                        columnSpacing: 8
                                        rowSpacing: 8

                                        CodexButton {
                                            Layout.fillWidth: true
                                            text: focusProvider() ? ("Pin " + focusProvider().shortLabel) : "Pin"
                                            glyph: root.glyphs.pin
                                            accent: focusProvider() ? statusColor(focusProvider()) : "#82FB9C"
                                            compact: true
                                            enabled: !!(focusProvider() && focusProvider().enabled)
                                            onClicked: {
                                                if (focusProvider()) {
                                                    root.runCodexbar(["providers", "pin", focusProvider().id])
                                                }
                                            }
                                        }

                                        CodexButton {
                                            Layout.fillWidth: true
                                            text: "Auto"
                                            glyph: root.glyphs.auto
                                            accent: "#82A7F4"
                                            compact: true
                                            onClicked: root.runCodexbar(["providers", "auto"])
                                        }

                                        CodexButton {
                                            Layout.fillWidth: true
                                            text: "Dashboard"
                                            glyph: root.glyphs.dashboard
                                            accent: "#F2C572"
                                            compact: true
                                            enabled: !!(focusProvider() && focusProvider().dashboardUrl)
                                            onClicked: {
                                                if (focusProvider() && focusProvider().dashboardUrl) {
                                                    root.runCodexbar(["open", "dashboard", focusProvider().id])
                                                }
                                            }
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    SectionHeader {
                                        text: "Provider"
                                        icon: root.glyphs.provider
                                        accent: "#8E97B5"
                                    }

                                    GridLayout {
                                        Layout.fillWidth: true
                                        columns: 4
                                        columnSpacing: 8
                                        rowSpacing: 8

                                        CodexButton {
                                            Layout.fillWidth: true
                                            text: focusProvider() && focusProvider().enabled ? "Deactivate" : "Activate"
                                            glyph: focusProvider() && focusProvider().enabled ? root.glyphs.close : root.glyphs.display
                                            accent: focusProvider() && focusProvider().enabled ? "#E06C75" : "#82FB9C"
                                            compact: true
                                            enabled: !!focusProvider()
                                            onClicked: {
                                                if (focusProvider()) {
                                                    root.providerCommand(focusProvider().enabled ? "deactivate" : "activate", focusProvider().id)
                                                }
                                            }
                                        }

                                        CodexButton {
                                            Layout.fillWidth: true
                                            text: focusProvider() && focusProvider().visible ? "Hide" : "Show"
                                            glyph: focusProvider() && focusProvider().visible ? root.glyphs.hidden : root.glyphs.shown
                                            accent: "#82A7F4"
                                            compact: true
                                            enabled: !!focusProvider()
                                            onClicked: {
                                                if (focusProvider()) {
                                                    root.providerCommand(focusProvider().visible ? "hide" : "show", focusProvider().id)
                                                }
                                            }
                                        }

                                        CodexButton {
                                            Layout.fillWidth: true
                                            text: focusProvider() && focusProvider().showInOverview ? "Drop Overview" : "Add Overview"
                                            glyph: root.glyphs.overview
                                            accent: "#F2C572"
                                            compact: true
                                            enabled: !!focusProvider()
                                            onClicked: {
                                                if (focusProvider()) {
                                                    root.overviewCommand(focusProvider().showInOverview ? "remove" : "add", focusProvider().id)
                                                }
                                            }
                                        }

                                        CodexButton {
                                            Layout.fillWidth: true
                                            text: focusProvider() && focusProvider().allowAutoSelect ? "Block Auto" : "Allow Auto"
                                            glyph: root.glyphs.auto
                                            accent: "#C4D2ED"
                                            compact: true
                                            enabled: !!focusProvider()
                                            onClicked: {
                                                if (focusProvider()) {
                                                    root.providerCommand(focusProvider().allowAutoSelect ? "block-auto" : "allow-auto", focusProvider().id)
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                SectionHeader {
                                    text: "Display"
                                    icon: root.glyphs.meter
                                    accent: "#8E97B5"
                                }

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 5
                                    columnSpacing: 8
                                    rowSpacing: 8

                                    CodexButton {
                                        Layout.fillWidth: true
                                        text: "Remaining"
                                        accent: viewData.summary.showUsedLabel === "Remaining" ? "#82FB9C" : "#6A6E95"
                                        compact: true
                                        onClicked: root.displayCommand("remaining")
                                    }

                                    CodexButton {
                                        Layout.fillWidth: true
                                        text: "Used"
                                        accent: viewData.summary.showUsedLabel === "Used" ? "#82A7F4" : "#6A6E95"
                                        compact: true
                                        onClicked: root.displayCommand("used")
                                    }

                                    CodexButton {
                                        Layout.fillWidth: true
                                        text: "Both"
                                        accent: viewData.summary.metricModeLabel === "both" ? "#82FB9C" : "#6A6E95"
                                        compact: true
                                        onClicked: root.displayCommand("mode", "both")
                                    }

                                    CodexButton {
                                        Layout.fillWidth: true
                                        text: "Percent"
                                        accent: viewData.summary.metricModeLabel === "percent" ? "#82FB9C" : "#6A6E95"
                                        compact: true
                                        onClicked: root.displayCommand("mode", "percent")
                                    }

                                    CodexButton {
                                        Layout.fillWidth: true
                                        text: "Pace"
                                        accent: viewData.summary.metricModeLabel === "pace" ? "#82FB9C" : "#6A6E95"
                                        compact: true
                                        onClicked: root.displayCommand("mode", "pace")
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                SectionHeader {
                                    text: "Runtime"
                                    icon: root.glyphs.settings
                                    accent: "#8E97B5"
                                }

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 8
                                    columnSpacing: 8
                                    rowSpacing: 8

                                    CodexButton {
                                        Layout.fillWidth: true
                                        text: "Manual"
                                        glyph: root.glyphs.pin
                                        accent: viewData.summary.refreshModeLabel === "Manual refresh" ? "#82FB9C" : "#6A6E95"
                                        compact: true
                                        onClicked: root.runtimeCommand("manual")
                                    }

                                    CodexButton {
                                        Layout.fillWidth: true
                                        text: "1m"
                                        accent: viewData.summary.refreshModeLabel === "60s refresh" ? "#82FB9C" : "#6A6E95"
                                        compact: true
                                        onClicked: root.runtimeCommand("interval", "60")
                                    }

                                    CodexButton {
                                        Layout.fillWidth: true
                                        text: "2m"
                                        accent: viewData.summary.refreshModeLabel === "120s refresh" ? "#82FB9C" : "#6A6E95"
                                        compact: true
                                        onClicked: root.runtimeCommand("interval", "120")
                                    }

                                    CodexButton {
                                        Layout.fillWidth: true
                                        text: "5m"
                                        accent: viewData.summary.refreshModeLabel === "300s refresh" ? "#82FB9C" : "#6A6E95"
                                        compact: true
                                        onClicked: root.runtimeCommand("interval", "300")
                                    }

                                    CodexButton {
                                        Layout.fillWidth: true
                                        text: viewData.summary.notificationsLabel === "Notify on" ? "Notify Off" : "Notify On"
                                        glyph: root.glyphs.bell
                                        accent: viewData.summary.notificationsLabel === "Notify on" ? "#82A7F4" : "#6A6E95"
                                        compact: true
                                        onClicked: root.notificationCommand(viewData.summary.notificationsLabel !== "Notify on")
                                    }

                                    CodexButton {
                                        Layout.fillWidth: true
                                        text: viewData.summary.privacyLabel === "Privacy on" ? "Show ID" : "Hide ID"
                                        glyph: root.glyphs.privacy
                                        accent: viewData.summary.privacyLabel === "Privacy on" ? "#F2C572" : "#6A6E95"
                                        compact: true
                                        onClicked: root.privacyCommand(viewData.summary.privacyLabel !== "Privacy on")
                                    }

                                    CodexButton {
                                        Layout.fillWidth: true
                                        text: "Status"
                                        glyph: root.glyphs.status
                                        accent: "#82A7F4"
                                        compact: true
                                        onClicked: root.runCodexbar(["status"])
                                    }

                                    CodexButton {
                                        Layout.fillWidth: true
                                        text: "Usage"
                                        glyph: root.glyphs.cost
                                        accent: "#F2C572"
                                        compact: true
                                        onClicked: root.runCodexbar(["cost"])
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
