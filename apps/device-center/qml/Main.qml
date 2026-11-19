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

    footer: Rectangle {
        color: window.surface
        Behavior on color { ColorAnimation { duration: 320 } }
        height: statusText.implicitHeight + 24
        Text {
            id: statusText
            anchors.fill: parent
            anchors.margins: 12
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: controller.lastError.length ? window.danger : window.txtDim
            Behavior on color { ColorAnimation { duration: 320 } }
            text: controller.lastError.length ? controller.lastError :
                controller.busy ? "Working…" : "Connection: " + controller.connectionState
        }
    }

    property int navIndex: 0

    // Reactive i18n helper
    function tr(key) {
        var _ = controller.currentLanguage
        return controller.t(key)
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
            txt: "#F4F6FA", txtDim: "#98A1B2", txtFaint: "#5C6473",
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
            txt: "#14233A", txtDim: "#53647C", txtFaint: "#7788A0",
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
            txt: "#F3F2EE", txtDim: "#AAADB4", txtFaint: "#7D818A",
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
        font.pixelSize: 10
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

        implicitHeight: compact ? 40 : 48
        // Padding is declared, not inherited, so implicitWidth can be derived
        // from it. Otherwise the control sizes contentItem to availableWidth,
        // the row is wider than it needs, and the slack lands on the right.
        topPadding: 0
        bottomPadding: 0
        leftPadding: compact ? 16 : 20
        rightPadding: leftPadding
        implicitWidth: pillRow.implicitWidth + leftPadding + rightPadding
        hoverEnabled: true
        scale: pressed ? 0.955 : (hovered ? 1.035 : 1.0)

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
                anchors.margins: -4
                radius: height / 2
                color: "transparent"
                border.width: 1
                border.color: pill.tint
                opacity: pill.active ? 0.4 : 0
                scale: pill.active ? 1.0 : 0.94
                Behavior on opacity { NumberAnimation { duration: window.tSlow } }
                Behavior on scale { NumberAnimation { duration: window.tSlow; easing.type: Easing.OutBack } }
            }
        }

        contentItem: RowLayout {
            id: pillRow
            // The glyph box is 24 units wide but most paths don't fill it, so
            // the optical gap is always a few px wider than this number.
            spacing: pill.compact ? 7 : 8
            Glyph {
                visible: pill.glyphPath !== ""
                path: pill.glyphPath
                size: pill.compact ? 17 : 20
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
        implicitWidth: 50
        implicitHeight: 28
        hoverEnabled: true

        indicator: Rectangle {
            implicitWidth: 50
            implicitHeight: 28
            radius: height / 2
            color: sw.checked ? window.accent : window.surfaceSunk
            border.width: 1
            border.color: sw.checked ? window.accent : (sw.hovered ? window.lineHi : window.line)
            Behavior on color { ColorAnimation { duration: window.tBase } }
            Behavior on border.color { ColorAnimation { duration: window.tBase } }

            Rectangle {
                width: 20
                height: 20
                radius: 10
                y: 4
                x: sw.checked ? parent.width - width - 4 : 4
                color: sw.checked ? window.accentFg : window.txtFaint
                Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
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
            scale: sl.pressed ? 1.25 : (sl.hovered ? 1.12 : 1.0)
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
                scale: vs.pressed ? 1.22 : (vs.hovered ? 1.1 : 1.0)
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
            font.pixelSize: 10
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

        HoverHandler { id: swHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: swTap; onTapped: window.applyTheme(sw2.themeKey) }

        Accessible.role: Accessible.RadioButton
        Accessible.name: window.tr("theme_" + themeKey)
        Accessible.checked: selected

        ToolTip.visible: swHover.hovered
        ToolTip.delay: 600
        ToolTip.text: window.tr("theme_" + themeKey) + " — " + window.tr("theme_" + themeKey + "_desc")

        // Selection ring
        Rectangle {
            id: ring2
            width: 60; height: 40
            radius: 10
            color: "transparent"
            border.width: 2
            border.color: sw2.selected ? window.accent
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
            scale: swTap.pressed ? 0.95 : 1.0
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
            Layout.preferredWidth: 258
            color: window.sidebar

            Rectangle {
                anchors.right: parent.right
                width: 1
                height: parent.height
                color: window.line
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 22
                spacing: 26

                // Brand. Two lines, set to the height of the mark — the same
                // lockup the site and the brand assets use.
                RowLayout {
                    spacing: 12
                    BrandTile {
                        Layout.preferredWidth: 42
                        Layout.preferredHeight: 42
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

                // Device badge with a live battery ring
                Card {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 84
                    active: controller.connected

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 13

                        Item {
                            Layout.preferredWidth: 46
                            Layout.preferredHeight: 46

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
                                    running: controller.isCharging
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
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
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
                                        running: controller.connected
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
                    }
                }

                // Navigation with a sliding indicator
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 6 * 44 + 5 * 6

                    // The indicator floats; items don't each carry their own.
                    Rectangle {
                        width: parent.width
                        height: 44
                        radius: 12
                        y: window.navIndex * 50
                        color: Qt.rgba(window.accent.r, window.accent.g, window.accent.b, 0.14)
                        border.width: 1
                        border.color: Qt.rgba(window.accent.r, window.accent.g, window.accent.b, 0.45)

                        Behavior on y {
                            NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
                        }

                        Rectangle {
                            width: 3
                            height: 18
                            radius: 2
                            x: -1
                            anchors.verticalCenter: parent.verticalCenter
                            color: window.accent
                        }
                    }

                    Repeater {
                        model: [
                            { idx: 0, key: "nav_overview",        glyph: window.icons.headphones },
                            { idx: 1, key: "nav_noise_control",   glyph: window.icons.shield },
                            { idx: 2, key: "nav_equalizer",       glyph: window.icons.sliders },
                            { idx: 3, key: "nav_audio_features",  glyph: window.icons.sparkle },
                            { idx: 4, key: "nav_device_switcher", glyph: window.icons.swap },
                            { idx: 5, key: "nav_settings",        glyph: window.icons.settings }
                        ]

                        delegate: Item {
                            id: navItem
                            required property var modelData
                            readonly property bool current: window.navIndex === modelData.idx

                            width: parent.width
                            height: 44
                            y: modelData.idx * 50

                            Rectangle {
                                anchors.fill: parent
                                radius: 12
                                color: (navHover.hovered && !navItem.current) ? window.surfaceHi : "transparent"
                                Behavior on color { ColorAnimation { duration: window.tFast } }
                            }

                            HoverHandler { id: navHover; cursorShape: Qt.PointingHandCursor }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 13

                                Glyph {
                                    path: navItem.modelData.glyph
                                    size: 19
                                    color: navItem.current ? window.accentInk
                                         : navHover.hovered ? window.txt : window.txtFaint
                                }

                                Text {
                                    textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    text: window.tr(navItem.modelData.key)
                                    color: navItem.current ? window.txt
                                         : navHover.hovered ? window.txtDim : window.txtFaint
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

                        Glyph { path: window.icons.bluetooth; size: 15; color: window.success }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                textFormat: Text.PlainText
                                text: "SDK Core"
                                color: window.txtDim
                                font.pixelSize: 11
                                font.weight: Font.Medium
                            }
                            Text {
                                textFormat: Text.PlainText
                                text: "IPC · RFCOMM V2"
                                color: window.txtFaint
                                font.pixelSize: 10
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 7
                            Layout.preferredHeight: 7
                            radius: 3.5
                            color: window.success
                        }
                    }
                }
            }
        }

        // ------------------------------------------------------
        // CONTENT
        // ------------------------------------------------------
        StackLayout {
            enabled: !controller.busy
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: window.navIndex

            // ==================================================
            // 1 · OVERVIEW
            // ==================================================
            ViewPage {
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 36
                    spacing: 22

                    // Header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        ColumnLayout {
                            spacing: 5
                            Eyebrow { text: controller.connected ? "Connected Device" : "Offline" }
                            Text {
                                textFormat: Text.PlainText
                                text: controller.deviceName
                                color: window.txt
                                font.pixelSize: 30
                                font.weight: Font.DemiBold
                                font.letterSpacing: -0.7
                            }
                            Text {
                                textFormat: Text.PlainText
                                visible: controller.batteryLeft >= 0 || controller.batteryRight >= 0 || controller.batteryCase >= 0
                                text: "L " + (controller.batteryLeft >= 0 ? controller.batteryLeft + "%" : "—")
                                    + " · R " + (controller.batteryRight >= 0 ? controller.batteryRight + "%" : "—")
                                    + " · Case " + (controller.batteryCase >= 0 ? controller.batteryCase + "%" : "—")
                                color: window.txtDim
                                font.pixelSize: 12
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Compact status chips
                        Repeater {
                            model: [
                                { k: "Codec", v: controller.codec },
                                { k: "Battery", v: controller.batteryLevel >= 0 ? controller.batteryLevel + "%" : "Unknown" },
                                { k: "Mode", v: controller.noiseControlMode === "unknown" ? "Unknown" : controller.noiseControlMode === "cancelling" ? "ANC"
                                              : controller.noiseControlMode === "ambient" ? "Ambient" : "Off" }
                            ]

                            delegate: Rectangle {
                                id: statChip
                                required property var modelData
                                implicitWidth: chipCol.implicitWidth + 30
                                implicitHeight: 54
                                radius: 14
                                color: window.surface
                                border.width: 1
                                border.color: window.line

                                ColumnLayout {
                                    id: chipCol
                                    anchors.centerIn: parent
                                    spacing: 3
                                    Eyebrow {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: statChip.modelData.k
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        Layout.alignment: Qt.AlignHCenter
                                        text: statChip.modelData.v
                                        color: window.txt
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }
                        }
                    }

                    // Hero
                    Card {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 24
                        clip: true

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 4

                            // The aura belongs to the product, not the card.
                            // Centering it here keeps the rings off the labels.
                            Item {
                                id: heroStage
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: 290
                                Layout.preferredHeight: 290

                                Bloom {
                                    anchors.centerIn: parent
                                    z: -1
                                    width: 470; height: 470
                                    tint: controller.noiseControlMode === "unknown" ? window.txtDim : controller.noiseControlMode === "cancelling" ? window.accent
                                        : controller.noiseControlMode === "ambient" ? window.ambientWarm
                                        : window.txtFaint
                                    strength: controller.noiseControlMode === "off" ? 0.05 : 0.18
                                    Behavior on strength { NumberAnimation { duration: window.tSlow } }
                                }

                                // Concentric rings. ANC pulls inward, Ambient opens outward.
                                Repeater {
                                    model: 3
                                    delegate: Rectangle {
                                        id: auraRing
                                        required property int index
                                        readonly property bool inward: controller.noiseControlMode === "cancelling"
                                        readonly property bool live: controller.noiseControlMode !== "off"

                                        anchors.centerIn: parent
                                        z: -1
                                        width: 252 + index * 58
                                        height: width
                                        radius: width / 2
                                        color: "transparent"
                                        border.width: 1
                                        border.color: inward ? window.accent : window.ambientWarm
                                        opacity: 0
                                        visible: live

                                        SequentialAnimation {
                                            running: auraRing.live
                                            loops: Animation.Infinite
                                            PauseAnimation { duration: auraRing.index * 700 }
                                            ParallelAnimation {
                                                NumberAnimation {
                                                    target: auraRing; property: "opacity"
                                                    from: 0.0; to: 0.28
                                                    duration: 900; easing.type: Easing.OutQuad
                                                }
                                                NumberAnimation {
                                                    target: auraRing; property: "scale"
                                                    from: auraRing.inward ? 1.12 : 0.90
                                                    to: 1.0
                                                    duration: 900; easing.type: Easing.OutQuad
                                                }
                                            }
                                            ParallelAnimation {
                                                NumberAnimation {
                                                    target: auraRing; property: "opacity"
                                                    to: 0.0
                                                    duration: 1200; easing.type: Easing.InQuad
                                                }
                                                NumberAnimation {
                                                    target: auraRing; property: "scale"
                                                    to: auraRing.inward ? 0.88 : 1.14
                                                    duration: 1200; easing.type: Easing.InQuad
                                                }
                                            }
                                            PauseAnimation { duration: 400 }
                                        }
                                    }
                                }

                                Image {
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectFit
                                    source: "../" + controller.heroImagePath
                                    opacity: controller.connected ? 1.0 : 0.35
                                    scale: heroHover.hovered ? 1.06 : 1.0

                                    Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                                    Behavior on opacity { NumberAnimation { duration: window.tSlow } }

                                    HoverHandler { id: heroHover }
                                }
                            }

                            Text {
                                textFormat: Text.PlainText
                                Layout.alignment: Qt.AlignHCenter
                                Layout.topMargin: 10
                                text: controller.noiseControlMode === "unknown" ? "Unknown" : controller.noiseControlMode === "cancelling" ? "Noise Cancelling"
                                    : controller.noiseControlMode === "ambient" ? "Ambient Sound"
                                    : "Processing Off"
                                color: window.txt
                                font.pixelSize: 18
                                font.weight: Font.DemiBold
                                font.letterSpacing: -0.2
                            }

                            Text {
                                textFormat: Text.PlainText
                                Layout.alignment: Qt.AlignHCenter
                                Layout.topMargin: 2
                                text: controller.noiseControlMode === "unknown" ? "Unknown" : controller.noiseControlMode === "cancelling" ? "The outside world is sealed out"
                                    : controller.noiseControlMode === "ambient" ? "Level " + controller.ambientLevel + " · hearing your surroundings"
                                    : "Straight signal, no processing"
                                color: window.txtFaint
                                font.pixelSize: 12
                            }

                            // Quick actions
                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.topMargin: 30
                                spacing: 11

                                PillButton {
                                    text: "Noise Cancelling"
                                    glyphPath: window.icons.shield
                                    tint: window.accent
                                    active: controller.noiseControlMode === "cancelling"
                                    onClicked: controller.setAnc(!active)
                                }

                                PillButton {
                                    text: "Ambient"
                                    glyphPath: window.icons.mic
                                    tint: window.ambientWarm
                                    active: controller.noiseControlMode === "ambient"
                                    onClicked: controller.setAmbient(controller.ambientLevel, controller.focusOnVoice)
                                }

                                PillButton {
                                    text: "Off"
                                    glyphPath: window.icons.power
                                    tint: window.txtDim
                                    active: controller.noiseControlMode === "off"
                                    onClicked: controller.setNoiseControlOff()
                                }
                            }

                            // Secondary: a link to another screen, not a fourth mode.
                            PillButton {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.topMargin: 12
                                compact: true
                                text: "EQ · " + controller.equalizerPresetName
                                glyphPath: window.icons.sliders
                                onClicked: window.navIndex = 2
                            }
                        }
                    }
                }
            }

            // ==================================================
            // 2 · NOISE CONTROL
            // ==================================================
            ViewPage {
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 36
                    spacing: 24

                    ColumnLayout {
                        spacing: 5
                        Eyebrow { text: "Isolation" }
                        Text {
                            textFormat: Text.PlainText
                            text: "Noise Control"
                            color: window.txt
                            font.pixelSize: 28
                            font.weight: Font.DemiBold
                            font.letterSpacing: -0.6
                        }
                        Text {
                            textFormat: Text.PlainText
                            text: "Choose how much of the world gets through."
                            color: window.txtDim
                            font.pixelSize: 13
                        }
                    }

                    // Mode cards — big targets, honest states
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 132
                        spacing: 14

                        Repeater {
                            model: [
                                { mode: "cancelling", label: "Noise Cancelling", glyph: window.icons.shield, desc: "Seal out the room", tint: window.accent },
                                { mode: "ambient",    label: "Ambient Sound",    glyph: window.icons.mic,    desc: "Let the room in",   tint: window.ambientWarm },
                                { mode: "off",        label: "Off",              glyph: window.icons.power,  desc: "No processing",     tint: window.txtDim }
                            ]

                            delegate: Card {
                                id: modeCard
                                required property var modelData
                                readonly property bool current: controller.noiseControlMode === modelData.mode

                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                active: current
                                hovered: modeHover.hovered
                                scale: modeTap.pressed ? 0.975 : (modeHover.hovered ? 1.012 : 1.0)

                                Behavior on scale {
                                    NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                                }

                                HoverHandler { id: modeHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    id: modeTap
                                    onTapped: {
                                        if (modeCard.modelData.mode === "cancelling") controller.setAnc(true)
                                        else if (modeCard.modelData.mode === "ambient") controller.setAmbient(controller.ambientLevel, controller.focusOnVoice)
                                        else controller.setNoiseControlOff()
                                    }
                                }

                                ColumnLayout {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: 20
                                    anchors.rightMargin: 20
                                    spacing: 12

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10

                                        Rectangle {
                                            Layout.preferredWidth: 42
                                            Layout.preferredHeight: 42
                                            radius: 13
                                            color: modeCard.current
                                                 ? Qt.rgba(modeCard.modelData.tint.r, modeCard.modelData.tint.g, modeCard.modelData.tint.b, 0.18)
                                                 : window.surfaceSunk
                                            border.width: 1
                                            border.color: modeCard.current
                                                 ? Qt.rgba(modeCard.modelData.tint.r, modeCard.modelData.tint.g, modeCard.modelData.tint.b, 0.5)
                                                 : window.line
                                            Behavior on color { ColorAnimation { duration: window.tBase } }
                                            Behavior on border.color { ColorAnimation { duration: window.tBase } }

                                            Glyph {
                                                anchors.centerIn: parent
                                                path: modeCard.modelData.glyph
                                                size: 21
                                                color: modeCard.current ? modeCard.modelData.tint : window.txtFaint
                                            }
                                        }

                                        Item { Layout.fillWidth: true }

                                        // Active dot, animated in
                                        Rectangle {
                                            Layout.preferredWidth: 9
                                            Layout.preferredHeight: 9
                                            radius: 4.5
                                            color: modeCard.modelData.tint
                                            opacity: modeCard.current ? 1 : 0
                                            scale: modeCard.current ? 1 : 0.4
                                            Behavior on opacity { NumberAnimation { duration: window.tBase } }
                                            Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 3 } }
                                        }
                                    }

                                    ColumnLayout {
                                        spacing: 2
                                        Text {
                                            textFormat: Text.PlainText
                                            text: modeCard.modelData.label
                                            color: window.txt
                                            font.pixelSize: 15
                                            font.weight: Font.DemiBold
                                        }
                                        Text {
                                            textFormat: Text.PlainText
                                            text: modeCard.modelData.desc
                                            color: window.txtFaint
                                            font.pixelSize: 12
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Ambient detail
                    Card {
                        id: ambientCard
                        Layout.fillWidth: true
                        Layout.preferredHeight: 178
                        readonly property bool live: controller.noiseControlMode === "ambient"
                        opacity: live ? 1.0 : 0.42
                        enabled: live
                        Behavior on opacity { NumberAnimation { duration: window.tSlow; easing.type: Easing.OutQuad } }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 22
                            spacing: 18

                            RowLayout {
                                Layout.fillWidth: true
                                ColumnLayout {
                                    spacing: 2
                                    Eyebrow { text: "Ambient" }
                                    Text {
                                        textFormat: Text.PlainText
                                        text: "Sound Level"
                                        color: window.txt
                                        font.pixelSize: 15
                                        font.weight: Font.DemiBold
                                    }
                                }
                                Item { Layout.fillWidth: true }
                                Rectangle {
                                    implicitWidth: 56
                                    implicitHeight: 34
                                    radius: 11
                                    color: Qt.rgba(window.ambientWarm.r, window.ambientWarm.g, window.ambientWarm.b, 0.16)
                                    border.width: 1
                                    border.color: Qt.rgba(window.ambientWarm.r, window.ambientWarm.g, window.ambientWarm.b, 0.5)
                                    Text {
                                        textFormat: Text.PlainText
                                        anchors.centerIn: parent
                                        text: Math.round(ambientSlider.value)
                                        color: window.ambientWarm
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }

                            NeoSlider {
                                id: ambientSlider
                                Layout.fillWidth: true
                                from: 1; to: 20; stepSize: 1
                                confirmedValue: controller.ambientLevel
                                onMoved: controller.setAmbient(Math.round(value), voiceSwitch.checked)
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text {
                                        textFormat: Text.PlainText
                                        text: "Focus on Voice"
                                        color: window.txt
                                        font.pixelSize: 13
                                        font.weight: Font.Medium
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        text: "Lift human speech, filter the low rumble"
                                        color: window.txtFaint
                                        font.pixelSize: 11
                                    }
                                }
                                NeoSwitch {
                                    id: voiceSwitch
                                    confirmedChecked: controller.focusOnVoice
                                    onToggled: controller.setAmbient(controller.ambientLevel, checked)
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // ==================================================
            // 3 · EQUALIZER
            // ==================================================
            ViewPage {
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 36
                    spacing: 20

                    ColumnLayout {
                        spacing: 5
                        Eyebrow { text: "Signature" }
                        Text {
                            textFormat: Text.PlainText
                            text: "Equalizer"
                            color: window.txt
                            font.pixelSize: 28
                            font.weight: Font.DemiBold
                            font.letterSpacing: -0.6
                        }
                        Text {
                            textFormat: Text.PlainText
                            text: controller.tenBandEqualizer ? "Ten bands, fine-grained."
                                  : "Five bands, plus dedicated Clear Bass."
                            color: window.txtDim
                            font.pixelSize: 13
                        }
                    }

                    // Presets — wrapping flow, not ten crushed columns
                    Flow {
                        Layout.fillWidth: true
                        spacing: 8

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

                                scale: chipTap.pressed ? 0.94 : (chipHover.hovered ? 1.04 : 1.0)
                                Behavior on scale {
                                    NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
                                }

                                HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { id: chipTap; onTapped: controller.setEqualizerPreset(chip.modelData.id) }

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

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 24
                            spacing: 14

                            RowLayout {
                                Layout.fillWidth: true
                                Eyebrow { text: controller.tenBandEqualizer ? "10-Band" : "5-Band · ±10 dB" }
                                Item { Layout.fillWidth: true }
                                Text {
                                    textFormat: Text.PlainText
                                    text: controller.equalizerPresetName
                                    color: window.accentInk
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                }
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
                                    text: "Clear Bass"
                                    color: window.txt
                                    font.pixelSize: 15
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    textFormat: Text.PlainText
                                    text: "Sub-bass weight, no distortion"
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
            // 4 · AUDIO FEATURES
            // ==================================================
            ViewPage {
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 36
                    spacing: 22

                    ColumnLayout {
                        spacing: 5
                        Eyebrow { text: "Behaviour" }
                        Text {
                            textFormat: Text.PlainText
                            text: "Sound & Device Features"
                            color: window.txt
                            font.pixelSize: 28
                            font.weight: Font.DemiBold
                            font.letterSpacing: -0.6
                        }
                        Text {
                            textFormat: Text.PlainText
                            text: "Upscaling, speak-to-chat, and power discipline."
                            color: window.txtDim
                            font.pixelSize: 13
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        rowSpacing: 14
                        columnSpacing: 14

                        Repeater {
                            model: [
                                { key: "dsee",     title: "DSEE Extreme",    desc: "AI restores the highs that compression threw away", glyph: window.icons.sparkle },
                                { key: "speak",    title: "Speak-to-Chat",   desc: "Pauses playback and opens ambient when you talk",   glyph: window.icons.mic },
                                { key: "adaptive", title: "Adaptive Volume", desc: "Balances level against your surroundings",          glyph: window.icons.sliders }
                            ]

                            delegate: Card {
                                id: featCard
                                required property var modelData
                                readonly property string featureKey: modelData.key === "speak" ? "speakToChat" : modelData.key === "adaptive" ? "adaptiveVolume" : "dsee"
                                readonly property var availability: controller.featureStatus[featureKey]
                                readonly property bool known: controller.connected && availability && availability.availability === "valid"
                                readonly property bool supported: modelData.key === "dsee" ? controller.hasDsee : modelData.key === "speak" ? controller.hasSpeakToChat : controller.hasAdaptiveVolume
                                enabled: supported && controller.connected
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
                                            text: featCard.modelData.title
                                            color: window.txt
                                            font.pixelSize: 15
                                            font.weight: Font.DemiBold
                                        }
                                        Text {
                                            textFormat: Text.PlainText
                                            Layout.fillWidth: true
                                            text: !featCard.supported ? "Not supported" : !featCard.known ? "State unknown — waiting for device" : featCard.modelData.desc
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
                                        text: "Auto Power-Off"
                                        color: window.txt
                                        font.pixelSize: 15
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        Layout.fillWidth: true
                                        text: "Shut down after idle or removal"
                                        color: window.txtFaint
                                        font.pixelSize: 11
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                ComboBox {
                                    id: powerCombo
                                    implicitWidth: 134
                                    implicitHeight: 38
                                    model: ["Off", "5 Minutes", "15 Minutes", "30 Minutes", "1 Hour", "3 Hours"]
                                    currentIndex: controller.featureStatus.autoPowerOff && controller.featureStatus.autoPowerOff.availability === "valid" ? controller.autoPowerOff : -1
                                    Connections {
                                        target: controller
                                        function onStateChanged() { powerCombo.currentIndex = Qt.binding(function() {
                                            return controller.featureStatus.autoPowerOff && controller.featureStatus.autoPowerOff.availability === "valid" ? controller.autoPowerOff : -1
                                        }) }
                                    }
                                    onActivated: controller.setAutoPowerOff(index)

                                    background: Rectangle {
                                        radius: 11
                                        color: powerCombo.hovered ? window.surfaceHi : window.surfaceSunk
                                        border.width: 1
                                        border.color: powerCombo.hovered ? window.lineHi : window.line
                                        Behavior on color { ColorAnimation { duration: window.tFast } }
                                    }

                                    contentItem: Text {
                                        textFormat: Text.PlainText
                                        leftPadding: 13
                                        rightPadding: 28
                                        text: powerCombo.displayText
                                        color: window.txt
                                        font.pixelSize: 12
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                    }

                                    indicator: Glyph {
                                        x: powerCombo.width - width - 12
                                        y: powerCombo.height / 2 - height / 2
                                        size: 14
                                        color: window.txtFaint
                                        path: window.icons.chevron
                                        rotation: powerCombo.popup.visible ? 180 : 0
                                        Behavior on rotation { NumberAnimation { duration: window.tBase } }
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // ==================================================
            // 5 · DEVICE SWITCHER
            // ==================================================
            ViewPage {
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 36
                    spacing: 22

                    ColumnLayout {
                        spacing: 5
                        Eyebrow { text: "Easy Switch" }
                        Text {
                            textFormat: Text.PlainText
                            text: "Paired Devices"
                            color: window.txt
                            font.pixelSize: 28
                            font.weight: Font.DemiBold
                            font.letterSpacing: -0.6
                        }
                        Text {
                            textFormat: Text.PlainText
                            text: "Hand the connection to another set without re-pairing."
                            color: window.txtDim
                            font.pixelSize: 13
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 11

                        Repeater {
                            model: controller.pairedDevices

                            delegate: Card {
                                id: devCard
                                required property var modelData
                                readonly property bool current: modelData.name === controller.deviceName

                                Layout.fillWidth: true
                                Layout.preferredHeight: 84
                                active: current
                                hovered: devHover.hovered
                                scale: (devHover.hovered && !current) ? 1.006 : 1.0
                                Behavior on scale { NumberAnimation { duration: window.tBase } }

                                HoverHandler { id: devHover }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 20
                                    anchors.rightMargin: 20
                                    spacing: 16

                                    Rectangle {
                                        Layout.preferredWidth: 48
                                        Layout.preferredHeight: 48
                                        radius: 15
                                        color: devCard.current ? Qt.rgba(window.accent.r, window.accent.g, window.accent.b, 0.18) : window.surfaceSunk
                                        border.width: 1
                                        border.color: devCard.current ? Qt.rgba(window.accent.r, window.accent.g, window.accent.b, 0.5) : window.line

                                        Glyph {
                                            anchors.centerIn: parent
                                            path: window.icons.headphones
                                            size: 22
                                            color: devCard.current ? window.accentInk : window.txtFaint
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 3
                                        Text {
                                            textFormat: Text.PlainText
                                            text: devCard.modelData.name
                                            color: window.txt
                                            font.pixelSize: 15
                                            font.weight: Font.DemiBold
                                        }
                                        RowLayout {
                                            spacing: 7
                                            Rectangle {
                                                Layout.preferredWidth: 6
                                                Layout.preferredHeight: 6
                                                radius: 3
                                                color: devCard.current ? window.success : window.txtFaint
                                            }
                                            Text {
                                                textFormat: Text.PlainText
                                                text: devCard.current ? window.tr("connected") : window.tr("available")
                                                color: devCard.current ? window.success : window.txtFaint
                                                font.pixelSize: 11
                                                font.weight: Font.Medium
                                            }
                                            Text {
                                                textFormat: Text.PlainText
                                                text: "·  " + devCard.modelData.address
                                                color: window.txtFaint
                                                font.pixelSize: 11
                                            }
                                        }
                                    }

                                    PillButton {
                                        // Fixed width so the action column lines
                                        // up down the list regardless of label.
                                        Layout.preferredWidth: 132
                                        Layout.alignment: Qt.AlignVCenter
                                        implicitHeight: 40
                                        text: devCard.current ? window.tr("active") : window.tr("connect")
                                        glyphPath: devCard.current ? "" : window.icons.swap
                                        active: devCard.current
                                        enabled: !devCard.current
                                        opacity: enabled ? 1.0 : 0.8
                                        onClicked: controller.connectDevice(devCard.modelData.address, devCard.modelData.name)
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // ==================================================
            // 6 · SETTINGS
            // ==================================================
            ViewPage {
                // Settings outgrew one screen once Appearance arrived; it
                // scrolls (trackpad momentum on macOS), the other pages don't.
                Flickable {
                    id: settingsFlick
                    anchors.fill: parent
                    contentWidth: width
                    contentHeight: settingsCol.implicitHeight + 72
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
                    x: 36
                    y: 36
                    width: settingsFlick.width - 72
                    spacing: 22

                    ColumnLayout {
                        spacing: 5
                        Eyebrow { text: window.tr("settings_eyebrow") }
                        Text {
                            textFormat: Text.PlainText
                            text: window.tr("settings_title")
                            color: window.txt
                            font.pixelSize: 28
                            font.weight: Font.DemiBold
                            font.letterSpacing: -0.6
                        }
                        Text {
                            textFormat: Text.PlainText
                            text: window.tr("settings_subtitle")
                            color: window.txtDim
                            font.pixelSize: 13
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

                    // Split Cards: About Application & Community/Donate
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
                                        Eyebrow { text: "Protocol Core" }
                                        Text {
                                            textFormat: Text.PlainText
                                            text: "MDR V1 & V2 (C++20)"
                                            color: window.txt
                                            font.pixelSize: 12
                                            font.weight: Font.Medium
                                        }
                                    }

                                    ColumnLayout {
                                        spacing: 2
                                        Eyebrow { text: "Framework" }
                                        Text {
                                            textFormat: Text.PlainText
                                            text: "Qt 6 Quick / QML"
                                            color: window.txt
                                            font.pixelSize: 12
                                            font.weight: Font.Medium
                                        }
                                    }

                                    ColumnLayout {
                                        spacing: 2
                                        Eyebrow { text: "License" }
                                        Text {
                                            textFormat: Text.PlainText
                                            text: "MIT Open Source"
                                            color: window.txt
                                            font.pixelSize: 12
                                            font.weight: Font.Medium
                                        }
                                    }
                                }
                            }
                        }

                        // Right Card: GitHub & Donate
                        Card {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 184

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 22
                                spacing: 14

                                RowLayout {
                                    spacing: 14
                                    Rectangle {
                                        Layout.preferredWidth: 42
                                        Layout.preferredHeight: 42
                                        radius: 12
                                        color: Qt.rgba(window.danger.r, window.danger.g, window.danger.b, 0.16)
                                        border.width: 1
                                        border.color: Qt.rgba(window.danger.r, window.danger.g, window.danger.b, 0.45)

                                        Glyph {
                                            anchors.centerIn: parent
                                            path: window.icons.heart
                                            size: 20
                                            color: window.danger
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Text {
                                            textFormat: Text.PlainText
                                            text: window.tr("links_support")
                                            color: window.txt
                                            font.pixelSize: 15
                                            font.weight: Font.DemiBold
                                        }
                                        Text {
                                            textFormat: Text.PlainText
                                            text: "GitHub & Sponsorship"
                                            color: window.txtDim
                                            font.pixelSize: 12
                                        }
                                    }
                                }

                                Text {
                                    textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    text: window.tr("donate_desc")
                                    color: window.txtDim
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }

                                RowLayout {
                                    spacing: 10

                                    PillButton {
                                        compact: true
                                        glyphPath: window.icons.github
                                        text: window.tr("btn_github")
                                        onClicked: controller.openUrl("https://github.com/marconvcm/sony-device-center")
                                    }

                                    PillButton {
                                        compact: true
                                        tint: window.danger
                                        glyphPath: window.icons.heart
                                        text: window.tr("btn_donate")
                                        onClicked: controller.openUrl("https://github.com/sponsors/marconvcm")
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
