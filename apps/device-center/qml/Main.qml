import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes

ApplicationWindow {
    id: window
    width: 1180
    height: 780
    minimumWidth: 980
    minimumHeight: 660
    visible: true
    title: "Sony Device Center — " + controller.deviceName
    color: bg

    // Errors only. Connection state is in the sidebar and progress in the
    // "Applying…" pill, so an always-on status line just repeated them.
    footer: Rectangle {
        visible: controller.lastError.length > 0
        color: Qt.rgba(window.danger.r, window.danger.g, window.danger.b, 0.12)
        height: visible ? statusText.implicitHeight + 24 : 0
        Rectangle { width: parent.width; height: 1; color: Qt.rgba(window.danger.r, window.danger.g, window.danger.b, 0.35) }
        Text {
            id: statusText
            anchors.left: parent.left
            anchors.right: dismissError.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 16
            anchors.rightMargin: 12
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: window.danger
            font.pixelSize: 12
            text: controller.lastError
        }
        PillButton {
            id: dismissError
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            compact: true
            text: window.tr("dismiss")
            onClicked: controller.clearError()
        }
    }

    property int navIndex: 0
    // Page order in the StackLayout and sidebar. Noise control lives on Home.
    readonly property int pageHome: 0
    readonly property int pageEq: 1
    readonly property int pageFeatures: 2
    readonly property int pageSettings: 3
    readonly property int sidebarWidth: 220

    // Reactive i18n helper
    function tr(key) {
        var _ = controller.currentLanguage
        return controller.t(key)
    }

    Popup {
        id: batteryHistoryPopup
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape
        width: Math.min(720, window.width - 32)
        height: Math.min(560, window.height - 32)
        x: Math.round((window.width - width) / 2)
        y: Math.round((window.height - height) / 2)
        // Padding, not anchors: Popup sizes contentItem itself, and anchors on
        // it left the rows at their implicit width.
        padding: 20
        background: Rectangle { color: window.surface; radius: 18; border.color: window.line }
        contentItem: ColumnLayout {
            spacing: 12
            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { text: controller.batteryHealth >= 0 ? window.tr("battery_health").arg(Math.round(controller.batteryHealth * 100)) : window.tr("battery_health_insufficient"); color: window.txt; font.pixelSize: 17; font.weight: Font.DemiBold }
                    Text {
                        text: controller.estimatedFullMinutes >= 0
                            ? window.tr("battery_full_charge").arg(window.formatBatteryDuration(controller.estimatedFullMinutes)).arg(controller.estimateSource === "measured" ? window.tr("battery_source_measured").arg(controller.estimateSampleDays) : window.tr("battery_source_spec"))
                            : window.tr("battery_estimate_unknown")
                        color: window.txtDim; font.pixelSize: 12
                    }
                }
                Item { Layout.fillWidth: true }
                PillButton { compact: true; text: "×"; Accessible.name: window.tr("dismiss"); onClicked: batteryHistoryPopup.close() }
            }
            RowLayout {
                Layout.fillWidth: true
                Segmented {
                    Layout.preferredWidth: 240
                    model: [
                        { key: "30", label: window.tr("battery_range_30"), glyph: "", tint: window.accent },
                        { key: "90", label: window.tr("battery_range_90"), glyph: "", tint: window.accent },
                        { key: "all", label: window.tr("battery_range_all"), glyph: "", tint: window.accent }
                    ]
                    current: historyChart.rangeDays >= 99999 ? "all" : String(historyChart.rangeDays)
                    onPicked: function(key) { historyChart.rangeDays = key === "all" ? 99999 : Number(key) }
                }
                Item { Layout.fillWidth: true }
            }
            BatteryHistoryChart {
                id: historyChart
                Layout.fillWidth: true
                Layout.fillHeight: true
                deviceController: controller
                rangeDays: 90
                accent: window.accent; accentFg: window.accentFg; txt: window.txt; txtDim: window.txtDim; txtFaint: window.txtFaint
                line: window.line; surface: window.surface; surfaceSunk: window.surfaceSunk; success: window.success
                tr: function(key) { return window.tr(key) }
            }
            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: window.tr("battery_history_help"); color: window.txtFaint; font.pixelSize: 10; wrapMode: Text.Wrap; elide: Text.ElideRight }
                Text { id: historyResult; visible: text.length > 0; color: window.txtDim; font.pixelSize: 10; elide: Text.ElideRight }
                PillButton { compact: true; text: window.tr("battery_export"); onClicked: historyResult.text = controller.exportBatteryHistoryWithDialog() ? window.tr("battery_export_ok") : window.tr("battery_export_cancel") }
                PillButton {
                    compact: true
                    tint: confirming ? window.danger : window.accent
                    active: confirming
                    property bool confirming: false
                    text: confirming ? window.tr("battery_clear_confirm") : window.tr("battery_clear")
                    onClicked: {
                        if (!confirming) confirming = true
                        else { controller.clearBatteryHistory(); confirming = false; historyResult.text = window.tr("battery_clear_done") }
                    }
                    id: historyClear
                }
            }
        }
    }

    // ==========================================================
    // DESIGN TOKENS
    // Every color in this file comes from here. No orphan hex.
    //
    // Three palettes share one set of token names; the controller only
    // persists the chosen id. Tuned for a Liquid Retina XDR panel:
    // no pure #000 behind bright text (mini-LED haloing), hairlines
    // that stay 1pt at 2x, and sRGB values macOS colour-manages to P3.
    //
    //   accent      fills, gradients' deep end, active borders
    //   accentSoft  gradients' light end
    //   accentInk   accent used as text or glyph on surfaces
    //   accentAlt   second atmospheric bloom
    //   accentFg    marks drawn on top of an accent fill (not "onAccent":
    //               QML reads on<Upper> names as signal handlers)
    //   knob        slider and switch handles
    //   cardFade    bottom stop of the card's light-source gradient
    // ==========================================================
    readonly property var themes: ({
        // Original look. Values unchanged from the single-theme build.
        midnight: {
            bg: "#0A0B0F", surface: "#14161E", surfaceHi: "#1B1E29", surfaceSunk: "#0E1016",
            cardFade: "#0E1016", line: "#22252F", lineHi: "#2F3341", sidebar: "#B80D0E13",
            accent: "#7C5CFF", accentSoft: "#A78BFA", accentInk: "#A78BFA", accentAlt: "#3B82F6",
            accentFg: "#FFFFFF", knob: "#FFFFFF",
            ambientWarm: "#F2A73B", success: "#2DD4A7", danger: "#FF5A5F",
            txt: "#F4F6FA", txtDim: "#98A1B2", txtFaint: "#7A8394",
            shadow: "#000000", shadowStrength: 0, bloomScale: 1.0, cardRadius: 18
        },
        // Light. Ice-blue canvas, white cards on soft blue-tinted shadows,
        // electric blue → sky gradients and a teal second voice.
        ice: {
            bg: "#EEF3FA", surface: "#FFFFFF", surfaceHi: "#F5F9FE", surfaceSunk: "#E7EEF7",
            cardFade: "#F7FAFE", line: "#DCE5F0", lineHi: "#C2D2E5", sidebar: "#C7FFFFFF",
            accent: "#0A6CFF", accentSoft: "#3FA8FF", accentInk: "#0A5FE0", accentAlt: "#00BFC4",
            accentFg: "#FFFFFF", knob: "#FFFFFF",
            ambientWarm: "#D97706", success: "#009C98", danger: "#E63950",
            txt: "#14233A", txtDim: "#53647C", txtFaint: "#66778F",
            shadow: "#1E4C8F", shadowStrength: 1, bloomScale: 0.95, cardRadius: 22
        },
        // Graphite. Flat charcoal layers, amber-yellow highlights, orange as
        // the second voice. Ambient moves to orange so it never reads as the
        // accent; marks on accent fills turn dark for contrast on yellow.
        amber: {
            bg: "#1C1D20", surface: "#2A2C31", surfaceHi: "#33363C", surfaceSunk: "#232428",
            cardFade: "#26282C", line: "#383B42", lineHi: "#4A4E57", sidebar: "#D9202124",
            accent: "#F5C542", accentSoft: "#FFDA70", accentInk: "#F7CB52", accentAlt: "#F2703A",
            accentFg: "#1C1D20", knob: "#F4F1E8",
            ambientWarm: "#F2703A", success: "#9CCB5A", danger: "#F2545B",
            txt: "#F3F2EE", txtDim: "#AAADB4", txtFaint: "#9094A0",
            shadow: "#000000", shadowStrength: 0, bloomScale: 0.45, cardRadius: 14
        }
    })
    readonly property var themeOrder: ["midnight", "ice", "amber"]
    readonly property string themeId: themes[controller.theme] ? controller.theme : "midnight"
    readonly property var tp: themes[themeId]

    readonly property color bg:            tp.bg
    readonly property color surface:       tp.surface
    readonly property color surfaceHi:     tp.surfaceHi
    readonly property color surfaceSunk:   tp.surfaceSunk
    readonly property color cardFade:      tp.cardFade
    readonly property color line:          tp.line
    readonly property color lineHi:        tp.lineHi
    readonly property color sidebar:       tp.sidebar

    readonly property color accent:        tp.accent
    readonly property color accentSoft:    tp.accentSoft
    readonly property color accentInk:     tp.accentInk
    readonly property color accentAlt:     tp.accentAlt
    readonly property color accentFg:      tp.accentFg
    readonly property color knob:          tp.knob
    readonly property color ambientWarm:   tp.ambientWarm
    readonly property color success:       tp.success
    readonly property color danger:        tp.danger

    readonly property color txt:           tp.txt
    readonly property color txtDim:        tp.txtDim
    readonly property color txtFaint:      tp.txtFaint

    readonly property color shadow:        tp.shadow
    readonly property real  shadowStrength: tp.shadowStrength
    readonly property real  bloomScale:    tp.bloomScale
    readonly property real  cardRadius:    tp.cardRadius

    // Palette entries are strings; Qt.lighter(_, 1) yields a color whose
    // channels can be read. Qt.alpha() would do this but needs newer Qt.
    function withAlpha(c, a) {
        var k = Qt.lighter(c, 1.0)
        return Qt.rgba(k.r, k.g, k.b, a)
    }
    function formatBatteryDuration(minutes) {
        var h = Math.floor(minutes / 60), m = minutes % 60
        return m === 0 ? window.tr("duration_hours").arg(h)
                       : window.tr("duration_hours_minutes").arg(h).arg(m)
    }

    // Toggles, so a second click on the badge closes the list again.
    function openDevicePicker() {
        if (devicePicker.visible) { devicePicker.close(); return }
        controller.refreshDiscoveredDevices()
        devicePicker.open()
    }

    // Theme switches cross-fade: freeze the current frame, swap tokens
    // underneath, then dissolve the snapshot. One animation instead of a
    // Behavior on every colour binding in the file.
    function applyTheme(id) {
        if (id === themeId || !themes[id]) return
        // The stage, not window.contentItem: the content item is created in
        // C++ and has no QML engine, so grabToImage refuses it.
        var root = stage
        var dpr = Screen.devicePixelRatio
        var ok = root.grabToImage(function(result) {
            themeSnapshot.source = result.url
            themeSnapshot.opacity = 1
            controller.setTheme(id)
            themeFade.restart()
        }, Qt.size(root.width * dpr, root.height * dpr))
        if (!ok) controller.setTheme(id)
    }

    // Mono face for the wordmark. Resolved against the installed families
    // rather than set through font.families: that property makes the engine
    // abort loading the component on Qt 6.11, and silently — no error text.
    readonly property string monoFamily: {
        var wanted = ["JetBrains Mono", "JetBrainsMono Nerd Font", "Cascadia Code",
                      "SF Mono", "Consolas", "DejaVu Sans Mono", "Liberation Mono"]
        var installed = Qt.fontFamilies()
        for (var i = 0; i < wanted.length; ++i)
            if (installed.indexOf(wanted[i]) !== -1)
                return wanted[i]
        return "monospace"
    }

    // Motion constants — one place to retune the whole app's feel.
    readonly property int   tFast:  140
    readonly property int   tBase:  200
    readonly property int   tSlow:  340

    // macOS System Settings → Accessibility → Display → Reduce motion.
    // Scales go flat and looping pulses stop; colour fades remain.
    // Desktop integration (menu bar icon, global shortcut, alerts). Absent
    // when Main.qml is loaded without main.cpp, e.g. by preview harnesses.
    readonly property var desk: typeof desktop !== "undefined" ? desktop : null
    readonly property bool reduceMotion: desk !== null && desk.reduceMotion
    // Controls do not grow on hover or shrink on press: macOS controls
    // respond with colour, not size, and the pointing-hand cursor is for links.

    // ==========================================================
    // REUSABLE PIECES
    // ==========================================================

    // Stroked SVG glyph. One string may hold several subpaths.
    component Glyph: Item {
        id: glyph
        property string path: ""
        property real size: 18
        property color color: window.txtDim
        property real weight: 1.8
        implicitWidth: size
        implicitHeight: size

        Shape {
            anchors.fill: parent
            antialiasing: true
            ShapePath {
                strokeColor: glyph.color
                // Path.scale scales geometry only — strokeWidth is already in
                // item pixels, so pre-multiplying it just makes icons look faint.
                strokeWidth: glyph.weight
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                scale: Qt.size(glyph.size / 24, glyph.size / 24)
                PathSvg { path: glyph.path }
            }
        }
        Behavior on color { ColorAnimation { duration: window.tFast } }
    }

    // Icon library. Named, not scattered as magic strings.
    readonly property var icons: ({
        headphones: "M4 17v-4a8 8 0 0 1 16 0v4 M3.5 15h3.2v6H3.5z M17.3 15h3.2v6h-3.2z",
        shield:     "M12 3l7.5 3v6.2c0 4.6-3.2 7.6-7.5 9-4.3-1.4-7.5-4.4-7.5-9V6z",
        mic:        "M12 3.5a3 3 0 0 1 3 3v5.2a3 3 0 0 1-6 0V6.5a3 3 0 0 1 3-3z M5 11a7 7 0 0 0 14 0 M12 18.2V21",
        sliders:    "M6 21v-6.4 M6 11.2V3 M12 21v-9.6 M12 8V3 M18 21v-4 M18 13.6V3 M3.6 13h4.8 M9.6 10h4.8 M15.6 15h4.8",
        sparkle:    "M11 3l1.7 4.9L17.6 9.6 12.7 11.3 11 16.2 9.3 11.3 4.4 9.6 9.3 7.9z M18 15.4l.75 2.1 2.1.75-2.1.75-.75 2.1-.75-2.1-2.1-.75 2.1-.75z",
        swap:       "M4 8.5h13l-3.4-3.4 M20 15.5H7l3.4 3.4",
        power:      "M12 3.5v8 M6.6 6.6a7.6 7.6 0 1 0 10.8 0",
        bolt:       "M13.2 2.5L4.8 13.4h6.3l-1.3 8.1 8.4-10.9h-6.3z",
        bluetooth:  "M7.5 7.5L16.5 13.4 12 17V3.6l4.5 3.6-9 6",
        chevron:    "M5 9l7 7 7-7",
        settings:   "M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z",
        globe:      "M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20z M2 12h20 M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z",
        github:     "M9 19c-5 1.5-5-2.5-7-3m14 6v-3.87a3.37 3.37 0 0 0-.94-2.61c3.14-.35 6.44-1.54 6.44-7A5.44 5.44 0 0 0 20 4.77 5.07 5.07 0 0 0 19.91 1S18.73.65 16 2.48a13.38 13.38 0 0 0-7 0C6.27.65 5.09 1 5.09 1A5.07 5.07 0 0 0 5 4.77a5.44 5.44 0 0 0-1.5 3.78c0 5.42 3.3 6.61 6.44 7A3.37 3.37 0 0 0 9 18.13V22",
        heart:      "M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z",
        check:      "M5 12.5l4.2 4.2L19 7.5",
        clock:      "M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z M12 7.5V12l3 2",
        reset:      "M4 12a8 8 0 1 0 2.3-5.6 M4 4.5v4h4",
        battery:    "M3.5 8h15v8h-15z M20.5 10.5v3 M6 10.5v3",
        keyboard:   "M3.5 6.5h17v11h-17z M7 10h.01 M10 10h.01 M13 10h.01 M16 10h.01 M7.5 14h9",
        bell:       "M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15z M10 20.5a2 2 0 0 0 4 0",
        menubar:    "M3.5 5h17v14h-17z M3.5 9h17 M15 7h2",
        palette:    "M12 3a9 9 0 1 0 0 18c1.1 0 1.8-.8 1.8-1.8 0-.5-.2-.9-.5-1.2-.3-.3-.5-.7-.5-1.2 0-1 .8-1.8 1.8-1.8H17a4 4 0 0 0 4-4c0-4.4-4-8-9-8z M7.5 11.5h.01 M10 7.5h.01 M14.5 7.5h.01 M17 11h.01",
        info:       "M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20z M12 16v-4 M12 8h.01",
        externalLink: "M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6 M15 3h6v6 M10 14L21 3"
    })

    // ==========================================================
    // BRAND
    // Geometry is a transcription of assets/mark.svg on its own
    // 24-unit grid, so the in-app mark and the shipped app icon are
    // the same drawing at every size. Edit the SVG and this together.
    // ==========================================================

    // The mark alone. Sealed left earcup (noise cancelling), open
    // right earcup (ambient) — the product in one glyph.
    component BrandMark: Item {
        id: brandMark
        property real size: 24
        property color color: window.accentFg
        // One SVG unit expressed in item pixels. ShapePath.scale only
        // scales geometry, so stroke widths have to be scaled by hand
        // or the mark thickens as it shrinks.
        readonly property real u: size / 24
        implicitWidth: size
        implicitHeight: size

        Shape {
            anchors.fill: parent
            antialiasing: true

            ShapePath {
                strokeColor: brandMark.color
                strokeWidth: 2 * brandMark.u
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                scale: Qt.size(brandMark.u, brandMark.u)
                PathSvg { path: "M4.6 13.2 A7.2 7.2 0 0 1 19 13.2" }
            }

            ShapePath {
                strokeColor: "transparent"
                strokeWidth: -1
                fillColor: brandMark.color
                scale: Qt.size(brandMark.u, brandMark.u)
                PathAngleArc {
                    centerX: 4.6; centerY: 16
                    radiusX: 2.6; radiusY: 2.6
                    startAngle: 0; sweepAngle: 360
                }
            }

            ShapePath {
                strokeColor: brandMark.color
                strokeWidth: 1.7 * brandMark.u
                fillColor: "transparent"
                scale: Qt.size(brandMark.u, brandMark.u)
                PathAngleArc {
                    centerX: 19; centerY: 16
                    radiusX: 2.2; radiusY: 2.2
                    startAngle: 0; sweepAngle: 360
                }
            }
        }

        Behavior on color { ColorAnimation { duration: window.tFast } }
    }

    // The mark in its gradient tile. Corner radius and mark inset are
    // the ratios from assets/lockup.svg (r13 and 26.67 on a 40px tile).
    component BrandTile: Rectangle {
        id: brandTile
        radius: width * 0.325
        gradient: Gradient {
            GradientStop { position: 0.0; color: window.accentSoft }
            GradientStop { position: 1.0; color: window.accent }
        }

        BrandMark {
            anchors.centerIn: parent
            size: brandTile.width * 0.6667
            color: window.accentFg
        }

        // Top sheen, matching the app icon's highlight pass.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0;  color: Qt.rgba(1, 1, 1, 0.16) }
                GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0.0) }
            }
        }
    }

    // Elevated card. Gradient fakes a top light source; hairline defines the edge.
    component Card: Rectangle {
        id: card
        property bool active: false
        property bool hovered: false
        radius: window.cardRadius
        border.width: 1
        border.color: active ? Qt.rgba(window.accent.r, window.accent.g, window.accent.b, 0.55)
                    : hovered ? window.lineHi : window.line
        gradient: Gradient {
            GradientStop { position: 0.0; color: card.hovered ? window.surfaceHi : window.surface }
            GradientStop { position: 1.0; color: window.cardFade }
        }
        Behavior on border.color { ColorAnimation { duration: window.tBase } }

        // Soft drop shadow for light themes: stacked translucent rounds
        // beneath the card (negative z draws under the parent). Avoids
        // QtQuick.Effects so distro Qt 6.4 builds keep loading this file.
        Repeater {
            model: window.shadowStrength > 0 ? 4 : 0
            delegate: Rectangle {
                required property int index
                z: -1
                anchors.fill: parent
                anchors.leftMargin: -(index * 3)
                anchors.rightMargin: -(index * 3)
                anchors.topMargin: -(index * 2) + 2
                anchors.bottomMargin: -(index * 4) - 4
                radius: card.radius + index * 3
                color: Qt.rgba(window.shadow.r, window.shadow.g, window.shadow.b,
                               (card.hovered ? 0.05 : 0.035) * window.shadowStrength)
                Behavior on color { ColorAnimation { duration: window.tBase } }
            }
        }
    }

    // Soft radial bloom. Atmosphere only — never carries information.
    component Bloom: Shape {
        id: bloom
        property color tint: window.accent
        property real strength: 0.22
        antialiasing: true
        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: bloom.width / 2
                centerY: bloom.height / 2
                centerRadius: bloom.width / 2
                focalX: centerX
                focalY: centerY
                GradientStop { position: 0.0; color: Qt.rgba(bloom.tint.r, bloom.tint.g, bloom.tint.b, bloom.strength * window.bloomScale) }
                GradientStop { position: 0.55; color: Qt.rgba(bloom.tint.r, bloom.tint.g, bloom.tint.b, bloom.strength * window.bloomScale * 0.35) }
                GradientStop { position: 1.0; color: Qt.rgba(bloom.tint.r, bloom.tint.g, bloom.tint.b, 0.0) }
            }
            startX: 0; startY: 0
            PathLine { x: bloom.width; y: 0 }
            PathLine { x: bloom.width; y: bloom.height }
            PathLine { x: 0; y: bloom.height }
        }
    }

    // Small uppercase label. Letter-spacing is what makes it read as deliberate.
    component Eyebrow: Text {
        textFormat: Text.PlainText
        color: window.txtFaint
        font.pixelSize: 11
        font.bold: true
        font.letterSpacing: 1.4
        font.capitalization: Font.AllUppercase
    }

    // The pill button. Press physics live here so every button feels identical.
    component PillButton: Button {
        id: pill
        property color tint: window.accent
        property bool active: false
        property string glyphPath: ""
        property bool compact: false

        implicitHeight: compact ? 28 : 32
        // Padding is declared, not inherited, so implicitWidth can be derived
        // from it. Otherwise the control sizes contentItem to availableWidth,
        // the row is wider than it needs, and the slack lands on the right.
        topPadding: 0
        bottomPadding: 0
        leftPadding: compact ? 12 : 14
        rightPadding: leftPadding
        implicitWidth: pillRow.implicitWidth + leftPadding + rightPadding
        hoverEnabled: true

        Behavior on scale {
            NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
        }

        background: Rectangle {
            radius: height / 2
            color: pill.active ? Qt.rgba(pill.tint.r, pill.tint.g, pill.tint.b, 0.16)
                 : pill.hovered ? window.surfaceHi : window.surface
            border.width: 1
            border.color: pill.active ? Qt.rgba(pill.tint.r, pill.tint.g, pill.tint.b, 0.8)
                        : pill.hovered ? window.lineHi : window.line

            Behavior on color { ColorAnimation { duration: window.tBase } }
            Behavior on border.color { ColorAnimation { duration: window.tBase } }

            // Halo ring — the difference between "on" and "on, and you felt it".
            Rectangle {
                anchors.fill: parent
                anchors.margins: -3
                radius: height / 2
                color: "transparent"
                border.width: 1
                border.color: pill.tint
                opacity: pill.active ? 0.25 : 0
                scale: pill.active ? 1.0 : 0.94
                Behavior on opacity { NumberAnimation { duration: window.tSlow } }
                Behavior on scale { NumberAnimation { duration: window.tSlow; easing.type: Easing.OutBack } }
            }
        }

        contentItem: RowLayout {
            id: pillRow
            // The glyph box is 24 units wide but most paths don't fill it, so
            // the optical gap is always a few px wider than this number.
            spacing: pill.compact ? 6 : 7
            Glyph {
                visible: pill.glyphPath !== ""
                path: pill.glyphPath
                size: pill.compact ? 14 : 16
                weight: 1.9
                color: pill.active ? pill.tint : window.txtDim
            }
            Text {
                textFormat: Text.PlainText
                text: pill.text
                color: pill.active ? window.txt : window.txtDim
                font.pixelSize: pill.compact ? 12 : 13
                font.weight: pill.active ? Font.DemiBold : Font.Medium
                Behavior on color { ColorAnimation { duration: window.tFast } }
            }
        }
    }

    // Custom switch. The stock one belongs to a different app.
    component NeoSwitch: Switch {
        id: sw
        property bool confirmedChecked: false
        checked: confirmedChecked
        Connections {
            target: controller
            function onStateChanged() { sw.checked = Qt.binding(function() { return sw.confirmedChecked }) }
        }
        implicitWidth: 38
        implicitHeight: 22
        hoverEnabled: true

        indicator: Rectangle {
            implicitWidth: 38
            implicitHeight: 22
            radius: height / 2
            color: sw.checked ? window.accent : window.surfaceSunk
            border.width: 1
            border.color: sw.checked ? window.accent : (sw.hovered ? window.lineHi : window.line)
            Behavior on color { ColorAnimation { duration: window.tBase } }
            Behavior on border.color { ColorAnimation { duration: window.tBase } }

            Rectangle {
                width: 18
                height: 18
                radius: 9
                y: 2
                x: sw.checked ? parent.width - width - 2 : 2
                color: sw.checked ? window.accentFg : window.txtFaint
                Behavior on x { NumberAnimation { duration: window.reduceMotion ? 0 : 160; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: window.tBase } }
            }
        }
        contentItem: Item {}
    }

    // Horizontal slider with a gradient fill and a handle that reacts.
    component NeoSlider: Slider {
        id: sl
        property real confirmedValue: 0
        value: confirmedValue
        Connections {
            target: controller
            function onStateChanged() { sl.value = Qt.binding(function() { return sl.confirmedValue }) }
        }
        implicitHeight: 26
        hoverEnabled: true

        background: Rectangle {
            x: sl.leftPadding
            y: sl.topPadding + sl.availableHeight / 2 - height / 2
            width: sl.availableWidth
            height: 6
            radius: 3
            color: window.surfaceSunk
            border.width: 1
            border.color: window.line

            Rectangle {
                width: sl.visualPosition * parent.width
                height: parent.height
                radius: 3
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: window.accent }
                    GradientStop { position: 1.0; color: window.accentSoft }
                }
            }
        }

        handle: Rectangle {
            x: sl.leftPadding + sl.visualPosition * (sl.availableWidth - width)
            y: sl.topPadding + sl.availableHeight / 2 - height / 2
            width: 18
            height: 18
            radius: 9
            color: window.knob
            border.width: 2
            border.color: window.accent
            Behavior on scale {
                NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 2.5 }
            }
        }
    }

    // Vertical EQ band. Fills outward from the zero line, because that's what it means.
    component BandSlider: ColumnLayout {
        id: band
        property string label: ""
        property real value: 0
        property real from: -10
        property real to: 10
        property real stepSize: 1
        property bool signedValues: true
        readonly property real zeroPosition: (0 - from) / (to - from)
        signal moved(real v)

        spacing: 10

        Text {
            textFormat: Text.PlainText
            Layout.alignment: Qt.AlignHCenter
            text: (band.signedValues && band.value > 0 ? "+" : "") + Math.round(band.value)
            color: Math.round(band.value) === 0 ? window.txtFaint : window.accentInk
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Behavior on color { ColorAnimation { duration: window.tFast } }
        }

        Slider {
            id: vs
            Layout.alignment: Qt.AlignHCenter
            Layout.fillHeight: true
            orientation: Qt.Vertical
            from: band.from
            to: band.to
            stepSize: band.stepSize
            value: band.value
            Connections {
                target: controller
                function onStateChanged() { vs.value = Qt.binding(function() { return band.value }) }
            }
            implicitWidth: 34
            hoverEnabled: true
            onMoved: band.moved(value)

            background: Rectangle {
                x: vs.leftPadding + vs.availableWidth / 2 - width / 2
                y: vs.topPadding
                width: 6
                height: vs.availableHeight
                radius: 3
                color: window.surfaceSunk
                border.width: 1
                border.color: window.line

                // The zero line. Small detail, big legibility win.
                Rectangle {
                    width: 14
                    height: 1
                    x: -4
                    y: parent.height * (1 - band.zeroPosition)
                    color: window.lineHi
                }

                Rectangle {
                    readonly property real p: 1 - vs.visualPosition
                    width: parent.width
                    y: parent.height * (1 - Math.max(band.zeroPosition, p))
                    height: parent.height * Math.abs(p - band.zeroPosition)
                    radius: 3
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: window.accentSoft }
                        GradientStop { position: 1.0; color: window.accent }
                    }
                }
            }

            handle: Rectangle {
                x: vs.leftPadding + vs.availableWidth / 2 - width / 2
                y: vs.topPadding + vs.visualPosition * (vs.availableHeight - height)
                width: 20
                height: 20
                radius: 10
                color: window.knob
                border.width: 2
                border.color: window.accent
                Behavior on scale {
                    NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 2.5 }
                }
            }
        }

        Text {
            textFormat: Text.PlainText
            Layout.alignment: Qt.AlignHCenter
            text: band.label
            color: window.txtFaint
            font.pixelSize: 11
            font.letterSpacing: 0.6
        }
    }

    // Compact theme swatch, in the manner of macOS System Settings →
    // Appearance: a thumbnail drawn from the target palette, its name
    // beneath, and a ring with a 2pt gap marking the current choice.
    component ThemeSwatch: Item {
        id: sw2
        property string themeKey: "midnight"
        readonly property var t: window.themes[themeKey]
        readonly property bool selected: window.themeId === themeKey

        implicitWidth: 60
        implicitHeight: 40 + 6 + swName.implicitHeight

        HoverHandler { id: swHover }
        TapHandler { id: swTap; onTapped: window.applyTheme(sw2.themeKey) }

        Accessible.role: Accessible.RadioButton
        Accessible.name: window.tr("theme_" + themeKey)
        Accessible.checked: selected
        activeFocusOnTab: true
        Keys.onReturnPressed: window.applyTheme(themeKey)
        Keys.onSpacePressed: window.applyTheme(themeKey)

        ToolTip.visible: swHover.hovered || activeFocus
        ToolTip.delay: 600
        ToolTip.text: window.tr("theme_" + themeKey) + " — " + window.tr("theme_" + themeKey + "_desc")

        // Selection ring
        Rectangle {
            id: ring2
            width: 60; height: 40
            radius: 10
            color: "transparent"
            border.width: 2
            border.color: sw2.selected || sw2.activeFocus ? window.accent
                        : swHover.hovered ? window.lineHi : "transparent"
            Behavior on border.color { ColorAnimation { duration: window.tBase } }
        }

        // Thumbnail
        Rectangle {
            id: thumb
            x: 3; y: 3
            width: 54; height: 34
            radius: 7
            color: sw2.t.bg
            clip: true
            border.width: 1
            border.color: sw2.t.lineHi
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }

            // Sidebar with the active nav item
            Rectangle {
                width: 16; height: parent.height
                color: sw2.t.surface
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: sw2.t.line }
                Rectangle {
                    x: 4; y: 5; width: 7; height: 7; radius: 2.5
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: sw2.t.accentSoft }
                        GradientStop { position: 1.0; color: sw2.t.accent }
                    }
                }
                Rectangle { x: 3; y: 16; width: 10; height: 3; radius: 1.5; color: sw2.t.accentInk }
                Rectangle { x: 3; y: 23; width: 8; height: 2; radius: 1; color: sw2.t.txtFaint }
            }
            // Card with a line of text and an accent toggle
            Rectangle {
                x: 20; y: 5
                width: parent.width - 24; height: 15
                radius: 3.5
                color: sw2.t.surface
                border.width: 1
                border.color: sw2.t.line
                Rectangle { x: 4; anchors.verticalCenter: parent.verticalCenter; width: 12; height: 2.5; radius: 1.25; color: sw2.t.txt }
                Rectangle {
                    anchors.right: parent.right; anchors.rightMargin: 3
                    anchors.verticalCenter: parent.verticalCenter
                    width: 12; height: 7; radius: 3.5
                    color: sw2.t.accent
                    Rectangle {
                        anchors.right: parent.right; anchors.rightMargin: 1
                        anchors.verticalCenter: parent.verticalCenter
                        width: 5; height: 5; radius: 2.5
                        color: sw2.t.accentFg
                    }
                }
            }
            // Slider in the accent, plus the ambient dot
            Rectangle {
                x: 20; y: 25; width: 20; height: 3; radius: 1.5
                color: sw2.t.accent
            }
            Rectangle {
                x: parent.width - 9; y: 23.5; width: 6; height: 6; radius: 3
                color: sw2.t.ambientWarm
            }
        }

        Text {
            id: swName
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            y: 46
            width: 66
            horizontalAlignment: Text.AlignHCenter
            text: window.tr("theme_" + sw2.themeKey + "_short")
            color: sw2.selected ? window.txt : window.txtDim
            font.pixelSize: 11
            font.weight: sw2.selected ? Font.DemiBold : Font.Normal
            elide: Text.ElideRight
            Behavior on color { ColorAnimation { duration: window.tFast } }
        }
    }

    // One settings row: icon tile, title and description, trailing control.
    // `divider` draws the hairline above it, so hidden rows leave no orphan.
    component SettingRow: ColumnLayout {
        id: srow
        property string glyphPath: ""
        property string title: ""
        property string desc: ""
        property bool divider: false
        default property alias trailing: slot.data
        Layout.fillWidth: true
        spacing: 16

        Rectangle {
            visible: srow.divider
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: window.line
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 16
            Rectangle {
                Layout.preferredWidth: 38
                Layout.preferredHeight: 38
                radius: 11
                color: Qt.rgba(window.accent.r, window.accent.g, window.accent.b, 0.14)
                border.width: 1
                border.color: Qt.rgba(window.accent.r, window.accent.g, window.accent.b, 0.35)
                Glyph { anchors.centerIn: parent; path: srow.glyphPath; size: 18; color: window.accentInk }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: srow.title
                    color: window.txt
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: srow.desc
                    color: window.txtDim
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
            }
            Item {
                id: slot
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: childrenRect.width
                implicitHeight: childrenRect.height
            }
        }
    }

    // Paired-headset menu under the sidebar badge (replaces the old Device
    // Switcher page). The current device is matched by address, falling
    // back to name for snapshots that carry no address.
    component DevicePicker: Popup {
        id: picker
        padding: 6
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
        background: Rectangle {
            radius: 12
            color: window.surface
            border.width: 1
            border.color: window.lineHi
        }
        contentItem: ColumnLayout {
            spacing: 2

            Text {
                textFormat: Text.PlainText
                Layout.leftMargin: 8
                Layout.topMargin: 4
                Layout.bottomMargin: 2
                text: window.tr("switcher_title")
                color: window.txtFaint
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }

            Repeater {
                model: controller.pairedDevices
                delegate: Rectangle {
                    id: pickRow
                    required property var modelData
                    readonly property bool current: controller.connected && (controller.deviceAddress.length
                        ? modelData.address === controller.deviceAddress : modelData.name === controller.deviceName)
                    Layout.fillWidth: true
                    implicitHeight: 40
                    radius: 8
                    color: pickHover.hovered || activeFocus ? window.surfaceHi : "transparent"
                    activeFocusOnTab: true
                    Accessible.role: Accessible.MenuItem
                    Accessible.name: modelData.name
                    Accessible.checked: current
                    function choose() {
                        picker.close()
                        if (!current) controller.connectDevice(modelData.address, modelData.name)
                    }
                    Keys.onReturnPressed: choose()
                    Keys.onSpacePressed: choose()
                    HoverHandler { id: pickHover }
                    TapHandler { onTapped: pickRow.choose() }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8
                        Glyph { path: window.icons.headphones; size: 15; color: pickRow.current ? window.accentInk : window.txtDim }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: pickRow.modelData.name
                                color: window.txt
                                font.pixelSize: 12
                                font.weight: pickRow.current ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
                            }
                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: pickRow.current ? window.tr("connected")
                                    : pickRow.modelData.systemConnected === true ? window.tr("connected_to_mac")
                                    : pickRow.modelData.paired === true ? window.tr("paired")
                                    : window.tr("available")
                                color: pickRow.current ? window.success : window.txtFaint
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }
                        Glyph { visible: pickRow.current; path: window.icons.check; size: 13; weight: 2.2; color: window.accentInk }
                    }
                }
            }

            Text {
                visible: controller.pairedDevices.length === 0
                textFormat: Text.PlainText
                Layout.fillWidth: true
                Layout.margins: 8
                text: window.tr("no_devices_found")
                color: window.txtDim
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            Rectangle { Layout.fillWidth: true; Layout.topMargin: 4; Layout.bottomMargin: 4; implicitHeight: 1; color: window.line }

            // No confirmation: turning it back on is one press on the headset.
            Rectangle {
                id: offRow
                visible: controller.connected && controller.hasPowerOff
                Layout.fillWidth: true
                implicitHeight: 30
                radius: 8
                color: offHover.hovered || activeFocus ? window.surfaceHi : "transparent"
                activeFocusOnTab: true
                Accessible.role: Accessible.MenuItem
                Accessible.name: window.tr("power_off_named").arg(controller.deviceName)
                function run() { picker.close(); controller.powerOffHeadphones() }
                Keys.onReturnPressed: run()
                HoverHandler { id: offHover }
                TapHandler { onTapped: offRow.run() }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    spacing: 8
                    Glyph { path: window.icons.power; size: 14; color: window.danger }
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: window.tr("power_off_named").arg(controller.deviceName)
                        color: window.danger
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }
            }

            Repeater {
                model: [
                    { key: "refresh_devices", glyph: window.icons.reset, mac: false },
                    { key: "bluetooth_settings", glyph: window.icons.bluetooth, mac: true }
                ]
                delegate: Rectangle {
                    id: actRow
                    required property var modelData
                    visible: !modelData.mac || Qt.platform.os === "osx"
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: 8
                    color: actHover.hovered || activeFocus ? window.surfaceHi : "transparent"
                    activeFocusOnTab: true
                    Accessible.role: Accessible.MenuItem
                    Accessible.name: window.tr(modelData.key)
                    function run() {
                        if (modelData.key === "refresh_devices") controller.refreshDiscoveredDevices()
                        else { picker.close(); controller.openUrl("x-apple.systempreferences:com.apple.BluetoothSettings") }
                    }
                    Keys.onReturnPressed: run()
                    HoverHandler { id: actHover }
                    TapHandler { onTapped: actRow.run() }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        spacing: 8
                        Glyph { path: actRow.modelData.glyph; size: 14; color: window.txtDim }
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: window.tr(actRow.modelData.key)
                            color: window.txtDim
                            font.pixelSize: 12
                        }
                    }
                }
            }
        }
    }

    // Styled ComboBox for new pickers; matches the language/power combos.
    component NeoCombo: ComboBox {
        id: nc
        // Bind this, not currentIndex. ComboBox resets currentIndex when its
        // model is replaced (a language switch rebuilds the labels) and on
        // activation, which would silently drop a plain binding.
        property int selectedIndex: -1
        function rebind() { nc.currentIndex = Qt.binding(function() { return nc.selectedIndex }) }
        currentIndex: selectedIndex
        onModelChanged: Qt.callLater(rebind)
        onActivated: Qt.callLater(rebind)
        implicitHeight: 38
        background: Rectangle {
            radius: 11
            color: nc.hovered ? window.surfaceHi : window.surfaceSunk
            border.width: nc.visualFocus ? 2 : 1
            border.color: nc.visualFocus ? window.accent : nc.hovered ? window.lineHi : window.line
            Behavior on color { ColorAnimation { duration: window.tFast } }
        }
        contentItem: Text {
            textFormat: Text.PlainText
            leftPadding: 13
            rightPadding: 28
            text: nc.displayText
            color: window.txt
            font.pixelSize: 12
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        indicator: Glyph {
            x: nc.width - width - 12
            y: nc.height / 2 - height / 2
            size: 14
            color: window.txtFaint
            path: window.icons.chevron
            rotation: nc.popup.visible ? 180 : 0
            Behavior on rotation { NumberAnimation { duration: window.tBase } }
        }
        popup: Popup {
            y: nc.height + 4
            width: nc.width
            implicitHeight: contentItem.implicitHeight + 12
            padding: 6
            background: Rectangle { radius: 12; color: window.surface; border.width: 1; border.color: window.lineHi }
            contentItem: ListView {
                clip: true
                implicitHeight: contentHeight
                model: nc.popup.visible ? nc.delegateModel : null
                currentIndex: nc.highlightedIndex
            }
        }
        delegate: ItemDelegate {
            id: ncDel
            required property int index
            required property var modelData
            width: nc.width - 12
            implicitHeight: 34
            highlighted: nc.highlightedIndex === index
            background: Rectangle {
                radius: 8
                color: ncDel.highlighted || ncDel.hovered ? window.surfaceHi : "transparent"
            }
            contentItem: Text {
                textFormat: Text.PlainText
                text: ncDel.modelData
                color: ncDel.index === nc.currentIndex ? window.accentInk : window.txt
                font.pixelSize: 12
                font.weight: ncDel.index === nc.currentIndex ? Font.DemiBold : Font.Normal
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    // macOS-style segmented control. `model` items: { key, label, glyph, tint }.
    component Segmented: Rectangle {
        id: seg
        property var model: []
        property string current: ""
        signal picked(string key)
        implicitHeight: 32
        radius: 8
        color: window.surfaceSunk
        border.width: 1
        border.color: window.line
        Accessible.role: Accessible.PageTabList

        Row {
            id: segRow
            anchors.fill: parent
            anchors.margins: 2
            Repeater {
                model: seg.model
                delegate: Rectangle {
                    id: segItem
                    required property var modelData
                    readonly property bool on: seg.current === modelData.key
                    width: segRow.width / Math.max(1, seg.model.length)
                    height: segRow.height
                    radius: 6
                    color: on ? Qt.rgba(modelData.tint.r, modelData.tint.g, modelData.tint.b, 0.18)
                       : segHover.hovered ? window.surfaceHi : "transparent"
                    border.width: on ? 1 : 0
                    border.color: Qt.rgba(modelData.tint.r, modelData.tint.g, modelData.tint.b, 0.6)
                    Behavior on color { ColorAnimation { duration: window.tFast } }

                    activeFocusOnTab: true
                    Keys.onReturnPressed: seg.picked(modelData.key)
                    Keys.onSpacePressed: seg.picked(modelData.key)
                    Accessible.role: Accessible.PageTab
                    Accessible.name: modelData.label
                    Accessible.selected: on
                    FocusRing { cornerRadius: 6 }

                    HoverHandler { id: segHover }
                    TapHandler { onTapped: seg.picked(segItem.modelData.key) }

                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        Glyph {
                            anchors.verticalCenter: parent.verticalCenter
                            path: segItem.modelData.glyph
                            size: 14
                            weight: 1.9
                            color: segItem.on ? segItem.modelData.tint : window.txtFaint
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: segItem.modelData.label
                            color: segItem.on ? window.txt : window.txtDim
                            font.pixelSize: 12
                            font.weight: segItem.on ? Font.DemiBold : Font.Normal
                        }
                    }
                }
            }
        }
    }

    // Smoothed response curve of the equalizer bands. Purely a picture of
    // the slider positions: it does not claim an acoustic measurement.
    component EqCurve: Canvas {
        id: curve
        property var bands: []
        property real from: -10
        property real to: 10
        property color stroke: window.accent
        readonly property string themeKey: window.themeId
        onBandsChanged: requestPaint()
        onThemeKeyChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var n = bands ? bands.length : 0
            var mid = height / 2
            ctx.strokeStyle = String(window.line)
            ctx.lineWidth = 1
            ctx.beginPath(); ctx.moveTo(0, mid); ctx.lineTo(width, mid); ctx.stroke()
            if (n < 2) return
            var pts = []
            for (var i = 0; i < n; ++i) {
                var v = Number(bands[i]) || 0
                var t = (v - from) / (to - from)
                pts.push({ x: (i + 0.5) * width / n, y: height - 4 - t * (height - 8) })
            }
            ctx.beginPath()
            ctx.moveTo(0, pts[0].y)
            ctx.lineTo(pts[0].x, pts[0].y)
            for (var j = 1; j < n; ++j) {
                var cx = (pts[j - 1].x + pts[j].x) / 2
                ctx.bezierCurveTo(cx, pts[j - 1].y, cx, pts[j].y, pts[j].x, pts[j].y)
            }
            ctx.lineTo(width, pts[n - 1].y)
            ctx.strokeStyle = String(stroke)
            ctx.lineWidth = 2
            ctx.lineJoin = "round"
            ctx.stroke()
            ctx.lineTo(width, height); ctx.lineTo(0, height); ctx.closePath()
            ctx.fillStyle = "rgba(" + Math.round(stroke.r * 255) + "," + Math.round(stroke.g * 255) + ","
                          + Math.round(stroke.b * 255) + ",0.10)"
            ctx.fill()
        }
    }

    // A quiet inline prompt keeps each page useful to browse while offline.
    // Device-specific controls remain visible in a disabled preview state.
    component OfflineState: Rectangle {
        visible: !controller.connected
        Layout.fillWidth: true
        Layout.preferredHeight: 54
        radius: 13
        color: window.surfaceSunk
        border.width: 1
        border.color: window.line
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 12
            spacing: 10
            Glyph { path: window.icons.bluetooth; size: 16; color: window.accentInk }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text { textFormat: Text.PlainText; text: window.tr("offline_title"); color: window.txt; font.pixelSize: 12; font.weight: Font.DemiBold }
                Text { textFormat: Text.PlainText; text: window.tr("offline_body"); color: window.txtDim; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
            }
            PillButton {
                compact: true
                active: true
                glyphPath: window.icons.swap
                text: window.tr("choose_device")
                onClicked: window.openDevicePicker()
            }
        }
    }

    // Every view enters the same way. Consistency is the whole point.
    component ViewPage: Item {
        id: page
        default property alias pageData: inner.data

        Item {
            id: inner
            width: parent.width
            height: parent.height
            opacity: 0
        }

        ParallelAnimation {
            id: entrance
            NumberAnimation { target: inner; property: "opacity"; from: 0; to: 1; duration: window.tBase + 60; easing.type: Easing.OutQuad }
            NumberAnimation { target: inner; property: "y"; from: 16; to: 0; duration: window.tSlow; easing.type: Easing.OutCubic }
        }

        onVisibleChanged: if (visible) entrance.restart()
        Component.onCompleted: if (visible) entrance.restart()
    }

    // Keyboard. "Ctrl" is ⌘ on macOS. ⌘, is the platform Preferences key.
    Shortcut { sequences: [StandardKey.Preferences]; onActivated: window.navIndex = window.pageSettings }
    Repeater {
        model: 4
        delegate: Item {
            required property int index
            Shortcut {
                sequence: "Ctrl+" + (index + 1)
                onActivated: window.navIndex = index
            }
        }
    }

    // Keyboard focus ring for custom controls (TapHandler items are not
    // focusable on their own). Drawn only while the parent has active focus.
    component FocusRing: Rectangle {
        property real cornerRadius: 12
        anchors.fill: parent
        anchors.margins: -3
        radius: cornerRadius + 3
        color: "transparent"
        border.width: 2
        border.color: window.accent
        visible: parent.activeFocus
        z: 10
    }

    // "Applying…" pill: local feedback that a command is in flight,
    // instead of a whole page silently ignoring clicks.
    Rectangle {
        id: busyPill
        z: 900
        visible: opacity > 0
        opacity: controller.busy ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: window.tBase } }
        // Bottom centre of the content column, clear of every page header.
        x: window.sidebarWidth + (window.contentItem.width - window.sidebarWidth - width) / 2
        y: window.contentItem.height - height - 20
        width: busyRow.implicitWidth + 26
        height: 30
        radius: 15
        color: window.surfaceHi
        border.width: 1
        border.color: window.lineHi
        Accessible.role: Accessible.StatusBar
        Accessible.name: window.tr("applying")
        RowLayout {
            id: busyRow
            anchors.centerIn: parent
            spacing: 8
            Item {
                Layout.preferredWidth: 14
                Layout.preferredHeight: 14
                Rectangle {
                    anchors.fill: parent
                    radius: 7
                    color: "transparent"
                    border.width: 2
                    border.color: window.line
                }
                Shape {
                    anchors.fill: parent
                    antialiasing: true
                    RotationAnimation on rotation {
                        running: busyPill.visible && !window.reduceMotion
                        from: 0; to: 360; duration: 900; loops: Animation.Infinite
                    }
                    ShapePath {
                        strokeColor: window.accent
                        strokeWidth: 2
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathAngleArc { centerX: 7; centerY: 7; radiusX: 6; radiusY: 6; startAngle: -90; sweepAngle: 100 }
                    }
                }
            }
            Text {
                textFormat: Text.PlainText
                text: window.tr("applying")
                color: window.txtDim
                font.pixelSize: 12
                font.weight: Font.Medium
            }
        }
    }

    // Cross-fade layer for theme switches (see applyTheme). Sits above
    // everything, ignores input, and is empty except mid-transition.
    Image {
        id: themeSnapshot
        z: 1000
        anchors.fill: parent
        opacity: 0
        visible: opacity > 0
        smooth: true
        cache: false
        NumberAnimation on opacity {
            id: themeFade
            running: false
            from: 1; to: 0
            duration: 320
            easing.type: Easing.InOutQuad
            onFinished: themeSnapshot.source = ""
        }
    }

    // Everything the theme paints lives on this stage, so one grab
    // captures the whole window for the cross-fade.
    Item {
    id: stage
    objectName: "themeStage"
    anchors.fill: parent

    // Opaque base so the cross-fade snapshot carries the old background.
    Rectangle {
        anchors.fill: parent
        color: window.bg
    }

    // ==========================================================
    // ATMOSPHERE
    // ==========================================================
    Bloom {
        width: 760; height: 760
        x: 140; y: -360
        tint: window.accent
        strength: 0.13
    }
    Bloom {
        width: 640; height: 640
        x: window.width - 380
        y: window.height - 340
        tint: window.accentAlt
        strength: 0.10
    }

    // ==========================================================
    // SHELL
    // ==========================================================
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ------------------------------------------------------
        // SIDEBAR
        // ------------------------------------------------------
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: window.sidebarWidth
            color: window.sidebar

            Rectangle {
                anchors.right: parent.right
                width: 1
                height: parent.height
                color: window.line
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 20

                // Brand. Two lines, set to the height of the mark — the same
                // lockup the site and the brand assets use.
                RowLayout {
                    spacing: 12
                    BrandTile {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                    }
                    ColumnLayout {
                        spacing: 2
                        Text {
                            textFormat: Text.PlainText
                            text: "DEVICE"
                            color: window.txtDim
                            font.family: window.monoFamily
                            font.pixelSize: 12
                            font.letterSpacing: 1.7
                        }
                        Text {
                            textFormat: Text.PlainText
                            text: "Center"
                            color: window.accentInk
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                            font.letterSpacing: -0.3
                        }
                    }
                }

                // Device badge with a live battery ring. It is also the device
                // picker: click (or Return) opens the list of paired headsets.
                Card {
                    id: deviceBadge
                    Layout.fillWidth: true
                    Layout.preferredHeight: 68
                    active: controller.connected
                    hovered: badgeHover.hovered || devicePicker.visible

                    HoverHandler { id: badgeHover }
                    TapHandler { onTapped: window.openDevicePicker() }
                    activeFocusOnTab: true
                    Keys.onReturnPressed: window.openDevicePicker()
                    Keys.onSpacePressed: window.openDevicePicker()
                    Accessible.role: Accessible.ButtonMenu
                    Accessible.name: window.tr("choose_device") + ": " + controller.deviceName
                    FocusRing { cornerRadius: window.cardRadius }

                    DevicePicker {
                        id: devicePicker
                        x: 0
                        y: deviceBadge.height + 6
                        width: deviceBadge.width
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        Item {
                            Layout.preferredWidth: 38
                            Layout.preferredHeight: 38

                            Canvas {
                                id: ring
                                anchors.fill: parent
                                property real level: controller.connected ? Math.max(0, controller.batteryLevel) : 0
                                readonly property string themeKey: window.themeId
                                Behavior on level { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
                                onLevelChanged: requestPaint()
                                onThemeKeyChanged: requestPaint()

                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.reset()
                                    var cx = width / 2, cy = height / 2, r = width / 2 - 4
                                    ctx.lineWidth = 3.5
                                    ctx.lineCap = "round"

                                    ctx.strokeStyle = String(window.line)
                                    ctx.beginPath()
                                    ctx.arc(cx, cy, r, 0, Math.PI * 2)
                                    ctx.stroke()

                                    if (level > 0) {
                                        ctx.strokeStyle = String(level > 20 ? window.success : window.danger)
                                        ctx.beginPath()
                                        ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * (level / 100))
                                        ctx.stroke()
                                    }
                                }
                            }

                            Glyph {
                                anchors.centerIn: parent
                                visible: controller.isCharging
                                path: window.icons.bolt
                                size: 16
                                color: window.success
                                weight: 2

                                SequentialAnimation on opacity {
                                    running: controller.isCharging && !window.reduceMotion
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutQuad }
                                    NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutQuad }
                                }
                            }

                            Text {
                                textFormat: Text.PlainText
                                anchors.centerIn: parent
                                visible: !controller.isCharging
                                text: controller.connected && controller.batteryLevel >= 0 ? controller.batteryLevel : "—"
                                color: window.txt
                                font.pixelSize: 15
                                font.weight: Font.Bold
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: controller.deviceName
                                color: window.txt
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            RowLayout {
                                spacing: 6
                                Rectangle {
                                    Layout.preferredWidth: 6
                                    Layout.preferredHeight: 6
                                    radius: 3
                                    color: controller.connected ? window.success : window.danger

                                    SequentialAnimation on opacity {
                                        running: controller.connected && !window.reduceMotion
                                        loops: Animation.Infinite
                                        NumberAnimation { to: 0.3; duration: 1100; easing.type: Easing.InOutQuad }
                                        NumberAnimation { to: 1.0; duration: 1100; easing.type: Easing.InOutQuad }
                                    }
                                }
                                Text {
                                    textFormat: Text.PlainText
                                    text: controller.connected ? window.tr("connected") : window.tr("disconnected")
                                    color: controller.connected ? window.txtDim : window.txtFaint
                                    font.pixelSize: 11
                                }
                            }
                        }

                        Glyph {
                            path: window.icons.chevron
                            size: 14
                            color: window.txtFaint
                            rotation: devicePicker.visible ? 180 : 0
                            Behavior on rotation { NumberAnimation { duration: window.reduceMotion ? 0 : window.tBase } }
                        }
                    }
                }

                // Navigation with a sliding indicator
                Item {
                    Layout.fillWidth: true
                    // macOS source-list metrics: 32 pt rows, 8 pt radius, a
                    // filled selection without a border or overshoot.
                    readonly property int rowH: 32
                    readonly property int rowStep: 36
                    Layout.preferredHeight: 4 * rowStep - (rowStep - rowH)

                    Rectangle {
                        width: parent.width
                        height: parent.rowH
                        radius: 8
                        y: window.navIndex * parent.rowStep
                        color: Qt.rgba(window.accent.r, window.accent.g, window.accent.b, 0.18)
                        Behavior on y {
                            NumberAnimation { duration: window.reduceMotion ? 0 : 200; easing.type: Easing.OutCubic }
                        }
                    }

                    Repeater {
                        model: [
                            { idx: window.pageHome,     key: "nav_overview",        glyph: window.icons.headphones },
                            { idx: window.pageEq,       key: "nav_equalizer",       glyph: window.icons.sliders },
                            { idx: window.pageFeatures, key: "nav_audio_features",  glyph: window.icons.sparkle },
                            { idx: window.pageSettings, key: "nav_settings",        glyph: window.icons.settings }
                        ]

                        delegate: Item {
                            id: navItem
                            required property var modelData
                            readonly property bool current: window.navIndex === modelData.idx

                            width: parent.width
                            height: parent.rowH
                            y: modelData.idx * parent.rowStep

                            activeFocusOnTab: true
                            Keys.onReturnPressed: window.navIndex = navItem.modelData.idx
                            Keys.onSpacePressed: window.navIndex = navItem.modelData.idx
                            Accessible.role: Accessible.PageTab
                            Accessible.name: window.tr(navItem.modelData.key)
                            Accessible.selected: navItem.current
                            FocusRing { cornerRadius: 8 }

                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: (navHover.hovered && !navItem.current) ? window.surfaceHi : "transparent"
                                Behavior on color { ColorAnimation { duration: window.tFast } }
                            }

                            HoverHandler { id: navHover }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 10

                                Glyph {
                                    path: navItem.modelData.glyph
                                    size: 16
                                    color: navItem.current ? window.accentInk : window.txtDim
                                }

                                Text {
                                    textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    text: window.tr(navItem.modelData.key)
                                    color: navItem.current ? window.txt : window.txtDim
                                    font.pixelSize: 13
                                    font.weight: navItem.current ? Font.DemiBold : Font.Normal
                                    Behavior on color { ColorAnimation { duration: window.tFast } }
                                }
                            }

                            TapHandler { onTapped: window.navIndex = navItem.modelData.idx }
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                // Transport / daemon status
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    radius: 12
                    color: window.surfaceSunk
                    border.width: 1
                    border.color: window.line

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 13
                        anchors.rightMargin: 13
                        spacing: 9

                        // Real link facts only: this used to be a fixed green
                        // "SDK Core · IPC · RFCOMM V2" regardless of state.
                        Glyph {
                            path: window.icons.bluetooth; size: 15
                            color: controller.connected ? window.success : window.txtFaint
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: "Bluetooth"
                                color: window.txtDim
                                font.pixelSize: 11
                                font.weight: Font.Medium
                            }
                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: controller.connected
                                      ? (controller.codec !== "Unknown" ? controller.codec : window.tr("connected"))
                                      : window.tr("state_" + controller.connectionState)
                                color: window.txtFaint
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 7
                            Layout.preferredHeight: 7
                            radius: 3.5
                            color: controller.connected ? window.success
                                 : controller.connectionState !== "disconnected" ? window.ambientWarm
                                 : window.txtFaint
                        }
                    }
                }
            }
        }

        // ------------------------------------------------------
        // CONTENT
        // ------------------------------------------------------
        StackLayout {
            // A command in flight blocks the device pages (the controller drops
            // overlapping commands), but Settings never talks to the headset.
            enabled: !controller.busy || window.navIndex === window.pageSettings
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: window.navIndex

            // ==================================================
            // 1 · HOME — the dashboard: device, battery, noise control,
            // and one-line summaries that link to EQ and Features.
            // ==================================================
            // Always shown: offline, the same layout dims instead of being
            // replaced, so the app keeps its shape and the next step is inline.
            ViewPage {
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 32
                    spacing: 16

                    // Header: name, and the facts that are not shown elsewhere.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: controller.deviceName.length ? controller.deviceName : window.tr("no_headphones")
                                color: window.txt
                                font.pixelSize: 24
                                font.weight: Font.DemiBold
                                font.letterSpacing: -0.4
                                elide: Text.ElideRight
                            }
                            RowLayout {
                                spacing: 6
                                Rectangle {
                                    Layout.preferredWidth: 7
                                    Layout.preferredHeight: 7
                                    radius: 3.5
                                    color: controller.connected ? window.success
                                         : controller.connectionState === "disconnected" ? window.txtFaint : window.ambientWarm
                                }
                                Text {
                                    textFormat: Text.PlainText
                                    text: controller.connected
                                          ? [window.tr("connected"),
                                             controller.codec !== "Unknown" ? controller.codec : "",
                                             controller.firmware.length ? window.tr("firmware") + " " + controller.firmware : ""]
                                            .filter(function(x) { return x.length > 0 }).join("  ·  ")
                                          : window.tr("state_" + controller.connectionState)
                                    color: window.txtDim
                                    font.pixelSize: 12
                                }
                            }
                        }
                        PillButton {
                            visible: !controller.connected
                            active: true
                            glyphPath: window.icons.swap
                            text: window.tr("choose_device")
                            onClicked: window.openDevicePicker()
                        }
                    }

                    // Both card rows stretch with the window (about 2:1), so the
                    // dashboard fills the page at any height instead of
                    // leaving an empty band under fixed-height cards.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: 320
                        Layout.minimumHeight: 268
                        spacing: 16

                        // Device and battery
                        Card {
                            id: homeDeviceCard
                            Layout.preferredWidth: 280
                            Layout.fillHeight: true

                            // Turn off sits on the device it acts on, where most
                            // sessions start. No confirmation: the headset's own
                            // button turns it back on.
                            PillButton {
                                z: 2
                                visible: controller.connected && controller.hasPowerOff
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 12
                                compact: true
                                glyphPath: window.icons.power
                                text: window.tr("turn_off")
                                Accessible.name: window.tr("power_off_named").arg(controller.deviceName)
                                ToolTip.visible: hovered
                                ToolTip.delay: 600
                                ToolTip.text: window.tr("power_off_named").arg(controller.deviceName)
                                onClicked: controller.powerOffHeadphones()
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 18
                                spacing: 10

                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Bloom {
                                        anchors.centerIn: parent
                                        width: Math.min(parent.width, parent.height) * 1.3
                                        height: width
                                        tint: controller.noiseControlMode === "cancelling" ? window.accent
                                            : controller.noiseControlMode === "ambient" ? window.ambientWarm : window.txtFaint
                                        strength: controller.noiseControlMode === "off" ? 0.05 : 0.16
                                    }
                                    Image {
                                        anchors.centerIn: parent
                                        opacity: controller.connected ? 1.0 : 0.35
                                        Behavior on opacity { NumberAnimation { duration: window.tSlow } }
                                        width: Math.min(parent.width, parent.height, 240)
                                        height: width
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                        mipmap: true
                                        source: "../" + controller.heroImagePath
                                    }
                                }

                                // One bar for over-ears, L/R/Case for earbuds.
                                Repeater {
                                    model: (controller.batteryLeft >= 0 || controller.batteryRight >= 0)
                                        ? [ { k: window.tr("battery_left_short"), v: controller.batteryLeft },
                                            { k: window.tr("battery_right_short"), v: controller.batteryRight },
                                            { k: window.tr("battery_case"), v: controller.batteryCase } ]
                                        : [ { k: window.tr("battery"), v: controller.batteryLevel } ]
                                    delegate: RowLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 10
                                        Text {
                                            textFormat: Text.PlainText
                                            Layout.preferredWidth: 52
                                            text: modelData.k
                                            color: window.txtDim
                                            font.pixelSize: 12
                                            elide: Text.ElideRight
                                        }
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 6
                                            radius: 3
                                            color: window.surfaceSunk
                                            border.width: 1
                                            border.color: window.line
                                            Rectangle {
                                                width: parent.width * Math.max(0, modelData.v) / 100
                                                height: parent.height
                                                radius: 3
                                                color: modelData.v > 20 ? window.success : window.danger
                                                Behavior on width { NumberAnimation { duration: window.reduceMotion ? 0 : 500; easing.type: Easing.OutCubic } }
                                            }
                                        }
                                        Text {
                                            textFormat: Text.PlainText
                                            Layout.preferredWidth: 64
                                            horizontalAlignment: Text.AlignRight
                                            text: modelData.v >= 0 ? modelData.v + "%" + (controller.isCharging && modelData.k === window.tr("battery") ? " ⚡" : "") : "—"
                                            color: modelData.v >= 0 && modelData.v <= 20 ? window.danger : window.txt
                                            font.pixelSize: 17
                                            font.weight: Font.Bold
                                            font.features: { "tnum": 1 }
                                        }
                                    }
                                }
                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: estimateLines.implicitHeight
                                    visible: controller.connected && (controller.estimatedFullMinutes >= 0 || controller.estimateSource === "spec")
                                    Column {
                                        id: estimateLines
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        spacing: 3
                                        Text {
                                            textFormat: Text.PlainText
                                            visible: !controller.isCharging && controller.estimatedRemainingMinutes >= 0
                                            text: window.tr("battery_remaining_to_10").arg(window.formatBatteryDuration(controller.estimatedRemainingMinutes))
                                            color: window.txtDim; font.pixelSize: 12; elide: Text.ElideRight
                                        }
                                        Text {
                                            textFormat: Text.PlainText
                                            text: window.tr("battery_full_charge").arg(window.formatBatteryDuration(controller.estimatedFullMinutes)).arg(
                                                controller.estimateSource === "measured"
                                                    ? window.tr("battery_source_measured").arg(controller.estimateSampleDays)
                                                    : window.tr("battery_source_spec"))
                                            color: window.txtDim; font.pixelSize: 12; elide: Text.ElideRight
                                        }
                                    }
                                    Text {
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        text: window.tr("battery_history_link")
                                        color: window.accentInk
                                        font.pixelSize: 11
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.ArrowCursor
                                        onClicked: batteryHistoryPopup.open()
                                    }
                                }
                            }
                        }

                        // Noise control: the main daily setting, so it gets the
                        // big card. Ambient detail appears only in Ambient.
                        Card {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 18
                                spacing: 14

                                Text {
                                    textFormat: Text.PlainText
                                    text: window.tr("nav_noise_control")
                                    color: window.txt
                                    font.pixelSize: 15
                                    font.weight: Font.DemiBold
                                }

                                Segmented {
                                    Layout.fillWidth: true
                                    enabled: controller.connected
                                    opacity: enabled ? 1 : 0.5
                                    current: controller.noiseControlMode
                                    model: [
                                        { key: "cancelling", label: window.tr("noise_cancelling"), glyph: window.icons.shield, tint: window.accent },
                                        { key: "ambient", label: window.tr("ambient_short"), glyph: window.icons.mic, tint: window.ambientWarm },
                                        { key: "off", label: window.tr("noise_control_off"), glyph: window.icons.power, tint: window.txtDim }
                                    ].filter(function(m) {
                                        return (m.key !== "cancelling" || controller.hasAnc) && (m.key !== "ambient" || controller.hasAmbient)
                                    })
                                    onPicked: function(key) {
                                        if (key === "cancelling") controller.setAnc(true)
                                        else if (key === "ambient") controller.setAmbient(controller.ambientLevel, controller.focusOnVoice)
                                        else controller.setNoiseControlOff()
                                    }
                                }

                                Text {
                                    textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    text: !controller.connected ? window.tr("nc_offline")
                                        : controller.noiseControlMode === "cancelling" ? window.tr("nc_hero_desc")
                                        : controller.noiseControlMode === "ambient" ? window.tr("ambient_card_desc")
                                        : controller.noiseControlMode === "off" ? window.tr("off_hero_desc")
                                        : window.tr("mode_unknown_desc")
                                    color: window.txtDim
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                }

                                ColumnLayout {
                                    visible: controller.connected && controller.noiseControlMode === "ambient"
                                    Layout.fillWidth: true
                                    spacing: 12

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            textFormat: Text.PlainText
                                            Layout.fillWidth: true
                                            text: window.tr("ambient_level")
                                            color: window.txt
                                            font.pixelSize: 13
                                            font.weight: Font.Medium
                                        }
                                        Text {
                                            textFormat: Text.PlainText
                                            text: Math.round(ambientSlider.value) + " / 20"
                                            color: window.ambientWarm
                                            font.pixelSize: 13
                                            font.weight: Font.DemiBold
                                        }
                                    }
                                    NeoSlider {
                                        id: ambientSlider
                                        Layout.fillWidth: true
                                        from: 1; to: 20; stepSize: 1
                                        confirmedValue: controller.ambientLevel
                                        onMoved: controller.setAmbient(Math.round(value), voiceSwitch.checked)
                                        Accessible.name: window.tr("ambient_level")
                                    }
                                    RowLayout {
                                        visible: controller.hasAmbient
                                        Layout.fillWidth: true
                                        spacing: 12
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            Text {
                                                textFormat: Text.PlainText
                                                text: window.tr("focus_on_voice")
                                                color: window.txt
                                                font.pixelSize: 13
                                                font.weight: Font.Medium
                                            }
                                            Text {
                                                textFormat: Text.PlainText
                                                Layout.fillWidth: true
                                                text: window.tr("focus_on_voice_desc")
                                                color: window.txtFaint
                                                font.pixelSize: 11
                                                elide: Text.ElideRight
                                            }
                                        }
                                        NeoSwitch {
                                            id: voiceSwitch
                                            confirmedChecked: controller.focusOnVoice
                                            onToggled: controller.setAmbient(controller.ambientLevel, checked)
                                            Accessible.name: window.tr("focus_on_voice")
                                        }
                                    }
                                }

                                // The remaining space shows the mode (shrinking under the
                                // Ambient controls) instead of leaving a void.
                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.minimumHeight: 0
                                    clip: true
                                    readonly property color tint: controller.noiseControlMode === "cancelling" ? window.accent
                                                                : controller.noiseControlMode === "ambient" ? window.ambientWarm
                                                                : controller.noiseControlMode === "off" ? window.txtFaint : window.lineHi
                                    Repeater {
                                        model: 3
                                        delegate: Rectangle {
                                            required property int index
                                            anchors.centerIn: parent
                                            width: Math.min(parent.width, parent.height) * (0.42 + index * 0.24)
                                            height: width
                                            radius: width / 2
                                            color: "transparent"
                                            border.width: 1
                                            border.color: parent.tint
                                            opacity: controller.noiseControlMode === "off" ? 0.18 : 0.38 - index * 0.11
                                        }
                                    }
                                    Rectangle {
                                        visible: parent.height >= 64
                                        anchors.centerIn: parent
                                        width: 56; height: 56; radius: 18
                                        color: Qt.rgba(parent.tint.r, parent.tint.g, parent.tint.b, 0.16)
                                        border.width: 1
                                        border.color: Qt.rgba(parent.tint.r, parent.tint.g, parent.tint.b, 0.5)
                                        Glyph {
                                            anchors.centerIn: parent
                                            size: 26
                                            path: controller.noiseControlMode === "cancelling" ? window.icons.shield
                                                : controller.noiseControlMode === "ambient" ? window.icons.mic : window.icons.power
                                            color: parent.parent.tint
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Summaries that link to the detail pages.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: 170
                        Layout.minimumHeight: 140
                        Layout.maximumHeight: 210
                        spacing: 16

                        Card {
                            visible: controller.hasEqualizer || !controller.connected
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 8
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        textFormat: Text.PlainText
                                        text: window.tr("nav_equalizer")
                                        color: window.txt
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        Layout.fillWidth: true
                                        text: controller.connected ? controller.equalizerPresetName : "—"
                                        color: window.accentInk
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }
                                    PillButton {
                                        compact: true
                                        text: window.tr("edit")
                                        onClicked: window.navIndex = window.pageEq
                                    }
                                }
                                EqCurve {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    opacity: controller.connected ? 1 : 0.35
                                    bands: controller.connected ? controller.equalizerBands : []
                                    from: controller.tenBandEqualizer ? 0 : -10
                                    to: controller.tenBandEqualizer ? 12 : 10
                                }
                            }
                        }

                        Card {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 8
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        textFormat: Text.PlainText
                                        Layout.fillWidth: true
                                        text: window.tr("features")
                                        color: window.txt
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                    }
                                    PillButton {
                                        compact: true
                                        text: window.tr("manage")
                                        onClicked: window.navIndex = window.pageFeatures
                                    }
                                }
                                Repeater {
                                    model: [
                                        { name: "DSEE Extreme", desc: window.tr("dsee_desc"), ok: controller.hasDsee, on: controller.dsee },
                                        { name: "Speak-to-Chat", desc: window.tr("s2c_desc"), ok: controller.hasSpeakToChat, on: controller.speakToChat },
                                        { name: "Adaptive Volume", desc: window.tr("adaptive_desc"), ok: controller.hasAdaptiveVolume, on: controller.adaptiveVolume }
                                    ].filter(function(f) { return f.ok && controller.connected })  // no stale states offline
                                    delegate: RowLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.topMargin: 4
                                        spacing: 10
                                        Rectangle {
                                            Layout.alignment: Qt.AlignTop
                                            Layout.topMargin: 5
                                            Layout.preferredWidth: 7
                                            Layout.preferredHeight: 7
                                            radius: 3.5
                                            color: modelData.on ? window.success : window.lineHi
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1
                                            Text {
                                                textFormat: Text.PlainText
                                                Layout.fillWidth: true
                                                text: modelData.name
                                                color: window.txt
                                                font.pixelSize: 12
                                                font.weight: Font.Medium
                                            }
                                            Text {
                                                textFormat: Text.PlainText
                                                Layout.fillWidth: true
                                                text: modelData.desc
                                                color: window.txtFaint
                                                font.pixelSize: 11
                                                elide: Text.ElideRight
                                            }
                                        }
                                        Text {
                                            textFormat: Text.PlainText
                                            text: modelData.on ? window.tr("feature_on") : window.tr("feature_off")
                                            color: modelData.on ? window.success : window.txtFaint
                                            font.pixelSize: 12
                                            font.weight: Font.Medium
                                        }
                                    }
                                }
                                Text {
                                    visible: !controller.connected
                                    textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    text: window.tr("features_offline")
                                    color: window.txtFaint
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                }
                                Item { Layout.fillHeight: true }
                            }
                        }
                    }
                }
            }

            // ==================================================
            // 2 · EQUALIZER
            // ==================================================
            ViewPage {
                ColumnLayout {
                    visible: true
                    anchors.fill: parent
                    anchors.margins: 32
                    spacing: 20

                    OfflineState { }

                    ColumnLayout {
                        spacing: 5
                        Text {
                            textFormat: Text.PlainText
                            text: window.tr("nav_equalizer")
                            color: window.txt
                            font.pixelSize: 22
                            font.weight: Font.DemiBold
                            font.letterSpacing: -0.3
                        }
                    }

                    // Presets — wrapping flow, not ten crushed columns
                    Flow {
                        Layout.fillWidth: true
                        spacing: 8
                        enabled: controller.connected
                        opacity: controller.connected ? 1 : 0.45

                        Repeater {
                            model: controller.tenBandEqualizer ? [
                                { id: 0x00, name: "Off" },
                                { id: 0xa0, name: "Custom" }
                            ] : [
                                { id: 0x00, name: "Off" },
                                { id: 0x16, name: "Bass Boost" },
                                { id: 0x15, name: "Treble Boost" },
                                { id: 0x14, name: "Vocal" },
                                { id: 0x10, name: "Bright" },
                                { id: 0x11, name: "Excited" },
                                { id: 0x12, name: "Mellow" },
                                { id: 0x13, name: "Relaxed" },
                                { id: 0x17, name: "Speech" },
                                { id: 0xa0, name: "Custom" }
                            ]

                            delegate: Rectangle {
                                id: chip
                                required property var modelData
                                readonly property bool current: controller.equalizerPreset === modelData.id

                                width: chipText.implicitWidth + 30
                                height: 38
                                radius: 19
                                color: current ? Qt.rgba(window.accent.r, window.accent.g, window.accent.b, 0.18)
                                     : chipHover.hovered ? window.surfaceHi : window.surface
                                border.width: 1
                                border.color: current ? Qt.rgba(window.accent.r, window.accent.g, window.accent.b, 0.7)
                                            : chipHover.hovered ? window.lineHi : window.line

                                Behavior on color { ColorAnimation { duration: window.tFast } }
                                Behavior on border.color { ColorAnimation { duration: window.tFast } }

                                Behavior on scale {
                                    NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
                                }

                                HoverHandler { id: chipHover }
                                TapHandler { id: chipTap; onTapped: controller.setEqualizerPreset(chip.modelData.id) }
                                activeFocusOnTab: true
                                Keys.onReturnPressed: controller.setEqualizerPreset(chip.modelData.id)
                                Keys.onSpacePressed: controller.setEqualizerPreset(chip.modelData.id)
                                Accessible.role: Accessible.RadioButton
                                Accessible.name: chip.modelData.name
                                Accessible.checked: chip.current
                                FocusRing { cornerRadius: 19 }

                                Text {
                                    textFormat: Text.PlainText
                                    id: chipText
                                    anchors.centerIn: parent
                                    text: chip.modelData.name
                                    color: chip.current ? window.txt : window.txtDim
                                    font.pixelSize: 12
                                    font.weight: chip.current ? Font.DemiBold : Font.Normal
                                    Behavior on color { ColorAnimation { duration: window.tFast } }
                                }
                            }
                        }
                    }

                    // Equalizer bands
                    Card {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        enabled: controller.connected
                        opacity: controller.connected ? 1 : 0.62

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 24
                            spacing: 14

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                Eyebrow { text: controller.tenBandEqualizer ? window.tr("eq_bands_10") : window.tr("eq_bands_5") }
                                Text {
                                    textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    text: controller.equalizerPresetName
                                    color: window.accentInk
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                                // Flat: zero bands keep Custom on the 5-band layout.
                                // The 10-band (XM6) neutral raw value is unverified,
                                // so there it selects the Off preset instead.
                                PillButton {
                                    compact: true
                                    glyphPath: window.icons.reset
                                    text: window.tr("eq_reset")
                                    onClicked: {
                                        if (controller.tenBandEqualizer) controller.setEqualizerPreset(0x00)
                                        else controller.setEqualizerCustom(0, [0, 0, 0, 0, 0])
                                    }
                                }
                            }

                            EqCurve {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 64
                                bands: controller.equalizerBands
                                from: controller.tenBandEqualizer ? 0 : -10
                                to: controller.tenBandEqualizer ? 12 : 10
                            }

                            RowLayout {
                                id: eqBandRow
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 4
                                readonly property int bandCount: controller.tenBandEqualizer ? 10 : 5

                                Repeater {
                                    // 10-band center frequencies read off Sony Sound Connect's
                                    // manual EQ for the WH-1000XM6 (standard ISO octave centers).
                                    model: controller.tenBandEqualizer
                                           ? ["31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
                                           : ["400", "1k", "2.5k", "6.3k", "16k"]

                                    delegate: BandSlider {
                                        id: bandItem
                                        required property int index
                                        required property var modelData

                                        // Pin each band to an equal 1/N share of the width the
                                        // row actually has to fill. This must be derived from the
                                        // row's PARENT width (externally fixed by the card), not
                                        // from eqBandRow.width: the row width is itself the sum of
                                        // these delegates, so binding to it feeds back on itself
                                        // and collapses every band to its 34px implicit width,
                                        // leaving them clustered at the left. A bare
                                        // Layout.fillWidth is not honored for this custom
                                        // ColumnLayout delegate, which is why the share is set
                                        // explicitly.
                                        Layout.preferredWidth: (eqBandRow.parent && eqBandRow.parent.width > 0)
                                            ? Math.max(implicitWidth,
                                                (eqBandRow.parent.width - (eqBandRow.bandCount - 1) * eqBandRow.spacing) / eqBandRow.bandCount)
                                            : implicitWidth
                                        Layout.fillHeight: true

                                        from: controller.tenBandEqualizer ? 0 : -10
                                        to: controller.tenBandEqualizer ? 12 : 10
                                        stepSize: 1
                                        signedValues: !controller.tenBandEqualizer
                                        label: modelData
                                        value: (controller.equalizerBands && controller.equalizerBands[index] !== undefined)
                                               ? controller.equalizerBands[index] : 0

                                        onMoved: function(v) {
                                            var next = []
                                            for (var i = 0; i < (controller.tenBandEqualizer ? 10 : 5); ++i) {
                                                next.push(i === bandItem.index
                                                    ? Math.round(v)
                                                    : ((controller.equalizerBands && controller.equalizerBands[i] !== undefined)
                                                        ? controller.equalizerBands[i] : 0))
                                            }
                                            controller.setEqualizerCustom(controller.tenBandEqualizer ? 0 : controller.clearBass, next)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Clear Bass
                    Card {
                        visible: controller.hasClearBass
                               || !controller.connected
                        enabled: controller.connected
                        opacity: controller.connected ? 1 : 0.62
                        Layout.fillWidth: true
                        Layout.preferredHeight: 96

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 22
                            anchors.rightMargin: 22
                            spacing: 22

                            ColumnLayout {
                                Layout.preferredWidth: 210
                                spacing: 2
                                Text {
                                    textFormat: Text.PlainText
                                    text: window.tr("clear_bass")
                                    color: window.txt
                                    font.pixelSize: 15
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    textFormat: Text.PlainText
                                    text: window.tr("clear_bass_desc")
                                    color: window.txtFaint
                                    font.pixelSize: 11
                                }
                            }

                            NeoSlider {
                                Layout.fillWidth: true
                                from: -10; to: 10; stepSize: 1
                                confirmedValue: controller.clearBass
                                onMoved: controller.setEqualizerCustom(Math.round(value), controller.equalizerBands)
                            }

                            Rectangle {
                                implicitWidth: 56
                                implicitHeight: 34
                                radius: 11
                                color: Qt.rgba(window.accent.r, window.accent.g, window.accent.b, 0.16)
                                border.width: 1
                                border.color: Qt.rgba(window.accent.r, window.accent.g, window.accent.b, 0.5)
                                Text {
                                    textFormat: Text.PlainText
                                    anchors.centerIn: parent
                                    text: (controller.clearBass > 0 ? "+" : "") + controller.clearBass
                                    color: window.accentInk
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                }
                            }
                        }
                    }
                }
            }

            // ==================================================
            // 3 · AUDIO FEATURES
            // ==================================================
            ViewPage {
                ColumnLayout {
                    visible: true
                    anchors.fill: parent
                    anchors.margins: 32
                    spacing: 22

                    OfflineState { }

                    ColumnLayout {
                        spacing: 5
                        Text {
                            textFormat: Text.PlainText
                            text: window.tr("feat_title")
                            color: window.txt
                            font.pixelSize: 22
                            font.weight: Font.DemiBold
                            font.letterSpacing: -0.3
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        rowSpacing: 14
                        columnSpacing: 14

                        Repeater {
                            model: [
                                { key: "dsee",     title: "DSEE Extreme",    desc: window.tr("dsee_desc"),     glyph: window.icons.sparkle },
                                { key: "speak",    title: "Speak-to-Chat",   desc: window.tr("s2c_desc"),      glyph: window.icons.mic },
                                { key: "adaptive", title: "Adaptive Volume", desc: window.tr("adaptive_desc"), glyph: window.icons.sliders }
                            ]

                            delegate: Card {
                                id: featCard
                                required property var modelData
                                readonly property string featureKey: modelData.key === "speak" ? "speakToChat" : modelData.key === "adaptive" ? "adaptiveVolume" : "dsee"
                                readonly property var availability: controller.featureStatus[featureKey]
                                readonly property bool known: controller.connected && availability && availability.availability === "valid"
                                readonly property bool supported: modelData.key === "dsee" ? controller.hasDsee : modelData.key === "speak" ? controller.hasSpeakToChat : controller.hasAdaptiveVolume
                                enabled: supported && controller.connected
                                opacity: controller.connected ? 1 : 0.62
                                visible: supported || !controller.connected
                                readonly property bool on: modelData.key === "dsee" ? controller.dsee
                                                         : modelData.key === "speak" ? controller.speakToChat
                                                         : controller.adaptiveVolume

                                Layout.fillWidth: true
                                Layout.preferredHeight: 112
                                hovered: featHover.hovered
                                active: on
                                HoverHandler { id: featHover }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 20
                                    anchors.rightMargin: 20
                                    spacing: 15

                                    Rectangle {
                                        Layout.preferredWidth: 44
                                        Layout.preferredHeight: 44
                                        radius: 14
                                        color: featCard.on ? Qt.rgba(window.accent.r, window.accent.g, window.accent.b, 0.18) : window.surfaceSunk
                                        border.width: 1
                                        border.color: featCard.on ? Qt.rgba(window.accent.r, window.accent.g, window.accent.b, 0.5) : window.line
                                        Behavior on color { ColorAnimation { duration: window.tBase } }
                                        Behavior on border.color { ColorAnimation { duration: window.tBase } }

                                        Glyph {
                                            anchors.centerIn: parent
                                            path: featCard.modelData.glyph
                                            size: 21
                                            color: featCard.on ? window.accentInk : window.txtFaint
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 3
                                        Text {
                                            textFormat: Text.PlainText
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                            text: featCard.modelData.title
                                            color: window.txt
                                            font.pixelSize: 15
                                            font.weight: Font.DemiBold
                                        }
                                        Text {
                                            textFormat: Text.PlainText
                                            Layout.fillWidth: true
                                            text: !controller.connected ? window.tr("features_offline")
                                                  : !featCard.supported ? window.tr("not_supported")
                                                  : !featCard.known ? window.tr("state_waiting") : featCard.modelData.desc
                                            color: window.txtFaint
                                            font.pixelSize: 11
                                            wrapMode: Text.WordWrap
                                        }
                                    }

                                    NeoSwitch {
                                        confirmedChecked: featCard.on
                                        onToggled: {
                                            if (featCard.modelData.key === "dsee") controller.setDsee(checked)
                                            else if (featCard.modelData.key === "speak") controller.setSpeakToChat(checked)
                                            else controller.setAdaptiveVolume(checked)
                                        }
                                    }
                                }
                            }
                        }

                        // Auto power-off — a choice, not a toggle
                        Card {
                            visible: controller.hasAutoPowerOff || !controller.connected
                            enabled: controller.connected
                            opacity: controller.connected ? 1 : 0.62
                            Layout.fillWidth: true
                            Layout.preferredHeight: 112
                            hovered: powerHover.hovered
                            HoverHandler { id: powerHover }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 20
                                anchors.rightMargin: 20
                                spacing: 15

                                Rectangle {
                                    Layout.preferredWidth: 44
                                    Layout.preferredHeight: 44
                                    radius: 14
                                    color: window.surfaceSunk
                                    border.width: 1
                                    border.color: window.line
                                    Glyph {
                                        anchors.centerIn: parent
                                        path: window.icons.power
                                        size: 21
                                        color: window.txtFaint
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3
                                    Text {
                                        textFormat: Text.PlainText
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: window.tr("auto_power_off")
                                        color: window.txt
                                        font.pixelSize: 15
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        Layout.fillWidth: true
                                        // A failed read says so instead of showing a blank box.
                                        text: powerCombo.status !== undefined && powerCombo.status.availability === "error"
                                              ? window.tr("apo_unreadable") + (powerCombo.status.error ? " (" + powerCombo.status.error + ")" : "")
                                              : controller.autoPowerOffMode === "takenOff" ? window.tr("apo_taken_off_desc")
                                              : window.tr("auto_power_off_desc")
                                        color: window.txtFaint
                                        font.pixelSize: 11
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                // Labels follow the protocol table (ProtocolV2 APO_CODES):
                                // Off, 5 min, 30 min, 1 h, 3 h, when taken off. The old
                                // list said 15/30/60/180 min and was off by one from 2.
                                // XM5-style models: Off or "when taken off" only.
                                NeoSwitch {
                                    visible: controller.autoPowerOffMode === "takenOff"
                                    confirmedChecked: controller.autoPowerOff === 5
                                    onToggled: controller.setAutoPowerOff(checked ? 5 : 0)
                                    Accessible.name: window.tr("apo_taken_off")
                                }
                                NeoCombo {
                                    id: powerCombo
                                    visible: controller.autoPowerOffMode !== "takenOff"
                                    implicitWidth: 150
                                    readonly property var status: controller.featureStatus.autoPowerOff
                                    readonly property bool known: status !== undefined && status.availability === "valid"
                                    model: [window.tr("apo_off"), window.tr("apo_5m"), window.tr("apo_30m"),
                                            window.tr("apo_1h"), window.tr("apo_3h"), window.tr("apo_taken_off")]
                                    selectedIndex: known ? controller.autoPowerOff : -1
                                    displayText: currentIndex < 0 ? window.tr("unknown") : currentText
                                    onActivated: function(index) { controller.setAutoPowerOff(index) }
                                }
                            }
                        }

                        // Speak-to-Chat auto-close. Only on models whose config
                        // frame is verified (WH-1000XM4); the headset cannot report
                        // it, so this shows the saved choice, re-sent on enable.
                        Card {
                            visible: controller.hasSpeakToChatTimeout || !controller.connected
                            Layout.fillWidth: true
                            Layout.columnSpan: 2
                            Layout.preferredHeight: 112
                            enabled: controller.connected
                            opacity: controller.connected ? 1 : 0.62
                            hovered: s2cHover.hovered
                            HoverHandler { id: s2cHover }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 20
                                anchors.rightMargin: 20
                                spacing: 15

                                Rectangle {
                                    Layout.preferredWidth: 44
                                    Layout.preferredHeight: 44
                                    radius: 14
                                    color: window.surfaceSunk
                                    border.width: 1
                                    border.color: window.line
                                    Glyph {
                                        anchors.centerIn: parent
                                        path: window.icons.clock
                                        size: 21
                                        color: window.txtFaint
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3
                                    Text {
                                        textFormat: Text.PlainText
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: window.tr("s2c_timeout")
                                        color: window.txt
                                        font.pixelSize: 15
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        Layout.fillWidth: true
                                        text: window.tr("s2c_timeout_desc")
                                        color: window.txtFaint
                                        font.pixelSize: 11
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                NeoCombo {
                                    implicitWidth: 134
                                    model: [window.tr("s2c_15s"), window.tr("s2c_30s"), window.tr("s2c_1m"), window.tr("s2c_never")]
                                    selectedIndex: controller.speakToChatTimeout
                                    onActivated: function(index) { controller.setSpeakToChatTimeout(index) }
                                }
                            }
                        }
                    }

                    // Features this model lacks, named once instead of shown as
                    // disabled switches that look clickable.
                    Text {
                        readonly property var missing: [
                            controller.hasDsee ? "" : "DSEE Extreme",
                            controller.hasSpeakToChat ? "" : "Speak-to-Chat",
                            controller.hasAdaptiveVolume ? "" : "Adaptive Volume",
                            controller.hasAutoPowerOff ? "" : window.tr("auto_power_off")
                        ].filter(function(x) { return x.length > 0 })
                        visible: missing.length > 0
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: window.tr("not_on_model").arg(missing.join(", "))
                        color: window.txtFaint
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // ==================================================
            // 4 · SETTINGS
            // ==================================================
            ViewPage {
                // Settings outgrew one screen once Appearance arrived; it
                // scrolls (trackpad momentum on macOS), the other pages don't.
                Flickable {
                    id: settingsFlick
                    anchors.fill: parent
                    contentWidth: width
                    contentHeight: settingsCol.implicitHeight + 64
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {
                        id: settingsBar
                        policy: settingsFlick.contentHeight > settingsFlick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                        contentItem: Rectangle {
                            implicitWidth: 6
                            radius: 3
                            color: settingsBar.pressed ? window.txtFaint : window.lineHi
                            opacity: settingsBar.active ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: window.tBase } }
                        }
                    }

                ColumnLayout {
                    id: settingsCol
                    x: 32
                    y: 32
                    width: settingsFlick.width - 64
                    spacing: 22

                    ColumnLayout {
                        spacing: 5
                        Text {
                            textFormat: Text.PlainText
                            text: window.tr("settings_title")
                            color: window.txt
                            font.pixelSize: 22
                            font.weight: Font.DemiBold
                            font.letterSpacing: -0.3
                        }
                    }

                    // Card 1: System & Interface Preferences
                    Card {
                        Layout.fillWidth: true
                        Layout.preferredHeight: systemCol.implicitHeight + 44

                        ColumnLayout {
                            id: systemCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 22
                            spacing: 16

                            // Row 1: Init with OS
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 16

                                Rectangle {
                                    Layout.preferredWidth: 38
                                    Layout.preferredHeight: 38
                                    radius: 11
                                    color: Qt.rgba(window.accent.r, window.accent.g, window.accent.b, 0.14)
                                    border.width: 1
                                    border.color: Qt.rgba(window.accent.r, window.accent.g, window.accent.b, 0.35)

                                    Glyph {
                                        anchors.centerIn: parent
                                        path: window.icons.power
                                        size: 18
                                        color: window.accentInk
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3
                                    Text {
                                        textFormat: Text.PlainText
                                        text: window.tr("init_with_os")
                                        color: window.txt
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        // fillWidth lets the row push its control to the trailing edge.
                                        Layout.fillWidth: true
                                        text: window.tr("init_with_os_desc")
                                        color: window.txtDim
                                        font.pixelSize: 12
                                    }
                                }

                                NeoSwitch {
                                    confirmedChecked: controller.autostart
                                    onToggled: controller.setAutostart(checked)
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: window.line
                            }

                            // Row 2: Language Selector
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 16

                                Rectangle {
                                    Layout.preferredWidth: 38
                                    Layout.preferredHeight: 38
                                    radius: 11
                                    color: Qt.rgba(window.accent.r, window.accent.g, window.accent.b, 0.14)
                                    border.width: 1
                                    border.color: Qt.rgba(window.accent.r, window.accent.g, window.accent.b, 0.35)

                                    Glyph {
                                        anchors.centerIn: parent
                                        path: window.icons.globe
                                        size: 18
                                        color: window.accentInk
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3
                                    Text {
                                        textFormat: Text.PlainText
                                        text: window.tr("language")
                                        color: window.txt
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        // fillWidth lets the row push its control to the trailing edge.
                                        Layout.fillWidth: true
                                        text: window.tr("language_desc")
                                        color: window.txtDim
                                        font.pixelSize: 12
                                    }
                                }

                                ComboBox {
                                    id: langCombo
                                    implicitWidth: 168
                                    implicitHeight: 38
                                    model: controller.availableLanguages
                                    textRole: "name"
                                    valueRole: "code"

                                    currentIndex: {
                                        var langs = controller.availableLanguages
                                        for (var i = 0; i < langs.length; ++i) {
                                            if (langs[i].code === controller.currentLanguage) return i
                                        }
                                        return 0
                                    }

                                    onActivated: {
                                        var item = model[index]
                                        if (item && item.code) {
                                            controller.setLanguage(item.code)
                                        }
                                    }

                                    background: Rectangle {
                                        radius: 11
                                        color: langCombo.hovered ? window.surfaceHi : window.surfaceSunk
                                        border.width: 1
                                        border.color: langCombo.hovered ? window.lineHi : window.line
                                        Behavior on color { ColorAnimation { duration: window.tFast } }
                                    }

                                    contentItem: Text {
                                        textFormat: Text.PlainText
                                        leftPadding: 14
                                        rightPadding: 28
                                        text: langCombo.displayText
                                        color: window.txt
                                        font.pixelSize: 13
                                        font.weight: Font.Medium
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                    }

                                    indicator: Glyph {
                                        x: langCombo.width - width - 12
                                        y: langCombo.height / 2 - height / 2
                                        size: 14
                                        color: window.txtFaint
                                        path: window.icons.chevron
                                        rotation: langCombo.popup.visible ? 180 : 0
                                        Behavior on rotation { NumberAnimation { duration: window.tBase } }
                                    }

                                    popup: Popup {
                                        y: langCombo.height + 4
                                        width: langCombo.width
                                        implicitHeight: Math.min(contentItem.implicitHeight + 12, 260)
                                        padding: 6
                                        background: Rectangle {
                                            radius: 12
                                            color: window.surface
                                            border.width: 1
                                            border.color: window.lineHi
                                        }
                                        contentItem: ListView {
                                            clip: true
                                            implicitHeight: contentHeight
                                            model: langCombo.popup.visible ? langCombo.delegateModel : null
                                            currentIndex: langCombo.highlightedIndex
                                            ScrollIndicator.vertical: ScrollIndicator {}
                                        }
                                    }

                                    delegate: ItemDelegate {
                                        id: langDel
                                        width: langCombo.width - 12
                                        implicitHeight: 36
                                        highlighted: langCombo.highlightedIndex === index
                                        hoverEnabled: true

                                        background: Rectangle {
                                            radius: 8
                                            color: langDel.highlighted ? window.surfaceHi : (langDel.hovered ? window.surfaceHi : "transparent")
                                            Behavior on color { ColorAnimation { duration: window.tFast } }
                                        }

                                        contentItem: RowLayout {
                                            spacing: 8
                                            Text {
                                                textFormat: Text.PlainText
                                                Layout.fillWidth: true
                                                text: modelData.name
                                                color: (modelData.code === controller.currentLanguage) ? window.accentInk : window.txt
                                                font.pixelSize: 13
                                                font.weight: (modelData.code === controller.currentLanguage) ? Font.DemiBold : Font.Normal
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                            Rectangle {
                                                visible: modelData.code === controller.currentLanguage
                                                width: 6
                                                height: 6
                                                radius: 3
                                                color: window.accent
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: window.line
                            }

                            // Row 3: Appearance
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 16

                                Rectangle {
                                    Layout.preferredWidth: 38
                                    Layout.preferredHeight: 38
                                    Layout.alignment: Qt.AlignTop
                                    radius: 11
                                    color: Qt.rgba(window.accent.r, window.accent.g, window.accent.b, 0.14)
                                    border.width: 1
                                    border.color: Qt.rgba(window.accent.r, window.accent.g, window.accent.b, 0.35)

                                    Glyph {
                                        anchors.centerIn: parent
                                        path: window.icons.palette
                                        size: 18
                                        color: window.accentInk
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignTop
                                    spacing: 3
                                    Text {
                                        textFormat: Text.PlainText
                                        text: window.tr("appearance")
                                        color: window.txt
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        Layout.fillWidth: true
                                        text: window.tr("appearance_desc")
                                        color: window.txtDim
                                        font.pixelSize: 12
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                Row {
                                    spacing: 8
                                    Repeater {
                                        model: window.themeOrder
                                        delegate: ThemeSwatch {
                                            required property string modelData
                                            themeKey: modelData
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Card 2: Menu bar — everything outside the window.
                    Card {
                        visible: window.desk !== null && window.desk.trayAvailable
                        Layout.fillWidth: true
                        Layout.preferredHeight: deskCol.implicitHeight + 44

                        ColumnLayout {
                            id: deskCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 22
                            spacing: 16

                            SettingRow {
                                visible: window.desk !== null && window.desk.trayAvailable
                                glyphPath: window.icons.menubar
                                title: window.tr("menubar_icon")
                                desc: window.tr("menubar_icon_desc")
                                NeoSwitch {
                                    confirmedChecked: window.desk !== null && window.desk.menuBarIcon
                                    onToggled: window.desk.setMenuBarIcon(checked)
                                }
                            }
                            SettingRow {
                                visible: window.desk !== null && window.desk.menuBarPercentAvailable
                                divider: true
                                glyphPath: window.icons.battery
                                title: window.tr("menubar_percent")
                                desc: window.tr("menubar_percent_desc")
                                enabled: window.desk !== null && window.desk.menuBarIcon
                                opacity: enabled ? 1 : 0.5
                                NeoSwitch {
                                    confirmedChecked: window.desk !== null && window.desk.menuBarPercent
                                    onToggled: window.desk.setMenuBarPercent(checked)
                                }
                            }
                            SettingRow {
                                visible: window.desk !== null && window.desk.trayAvailable
                                divider: true
                                glyphPath: window.icons.bell
                                title: window.tr("battery_alerts")
                                desc: window.tr("battery_alerts_desc")
                                enabled: window.desk !== null && window.desk.menuBarIcon
                                opacity: enabled ? 1 : 0.5
                                NeoSwitch {
                                    confirmedChecked: window.desk !== null && window.desk.batteryAlerts
                                    onToggled: window.desk.setBatteryAlerts(checked)
                                }
                            }
                        }
                    }

                    // About Application
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 18

                        // Left Card: About App & Version
                        Card {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 184

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 22
                                spacing: 14

                                RowLayout {
                                    spacing: 14
                                    BrandTile {
                                        Layout.preferredWidth: 42
                                        Layout.preferredHeight: 42
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Text {
                                            textFormat: Text.PlainText
                                            text: window.tr("about_app")
                                            color: window.txt
                                            font.pixelSize: 15
                                            font.weight: Font.DemiBold
                                        }
                                        Text {
                                            textFormat: Text.PlainText
                                            text: "Sony Device Center"
                                            color: window.txtDim
                                            font.pixelSize: 12
                                        }
                                    }

                                    Rectangle {
                                        Layout.preferredHeight: 28
                                        Layout.preferredWidth: verLabel.implicitWidth + 20
                                        radius: 14
                                        color: window.surfaceSunk
                                        border.width: 1
                                        border.color: window.lineHi

                                        Text {
                                            textFormat: Text.PlainText
                                            id: verLabel
                                            anchors.centerIn: parent
                                            text: "v" + controller.appVersion
                                            color: window.accentInk
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 1
                                    color: window.line
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 16

                                    ColumnLayout {
                                        spacing: 2
                                        Eyebrow { text: window.tr("about_license") }
                                        Text {
                                            textFormat: Text.PlainText
                                            text: window.tr("about_license_value")
                                            color: window.txt
                                            font.pixelSize: 12
                                            font.weight: Font.Medium
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Independent-project notice. It lives on the page rather
                    // than inside the About card because it is a trademark
                    // statement, not a detail about the build.
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 10
                        Layout.preferredHeight: 1
                        color: window.line
                    }

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: window.tr("disclaimer")
                        color: window.txtFaint
                        font.pixelSize: 12
                        lineHeight: 1.4
                        wrapMode: Text.WordWrap
                    }
                }
                }
            }
        }
    }
    } // stage
}
