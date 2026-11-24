import QtQuick

Item {
    id: root
    property var deviceController
    property int rangeDays: 90
    property color accent
    property color accentFg
    property color txt
    property color txtDim
    property color txtFaint
    property color line
    property color surface
    property color surfaceSunk
    property color success
    property var tr: function(key) { return key }
    property var shownDays: []
    property real tooltipX: -1000
    property real tooltipY: -1000
    property string tooltipText: ""

    function updateRange() {
        var days = root.deviceController.batteryHistoryDays || []
        if (rangeDays >= 99999) {
            shownDays = days
        } else {
            let cutoff = new Date(); cutoff.setHours(0, 0, 0, 0)
            cutoff.setDate(cutoff.getDate() - rangeDays)
            shownDays = days.filter(function(p) { return new Date(p.date + "T00:00:00") >= cutoff })
        }
        chart.requestPaint()
    }
    onRangeDaysChanged: updateRange()
    onAccentChanged: chart.requestPaint()
    onAccentFgChanged: chart.requestPaint()
    onTxtFaintChanged: chart.requestPaint()
    onLineChanged: chart.requestPaint()
    onSuccessChanged: chart.requestPaint()
    Connections { target: root.deviceController; function onBatteryHistoryChanged() { root.updateRange() } }
    Component.onCompleted: updateRange()

    Canvas {
        id: chart
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d"), w = width, h = height
            ctx.clearRect(0, 0, w, h)
            var pts = root.shownDays
            if (!pts.length) {
                ctx.fillStyle = root.txtFaint; ctx.font = "13px sans-serif"
                ctx.textAlign = "center"; ctx.textBaseline = "middle"
                ctx.fillText(root.tr("battery_history_empty"), w / 2, h / 2)
                root.tooltipX = -1000
                return
            }
            var dayMs = 86400000
            var dates = pts.map(function(p) { return new Date(p.date + "T00:00:00").getTime() })
            var dataStart = Math.min.apply(null, dates), dataEnd = Math.max.apply(null, dates)
            var today = new Date(); today.setHours(0, 0, 0, 0)
            var start = root.rangeDays >= 99999 ? dataStart : today.getTime() - root.rangeDays * dayMs
            var end = root.rangeDays >= 99999 ? dataEnd : today.getTime()
            if (end <= start) end = start + dayMs
            var trend = (root.deviceController.batteryTrend || []).filter(function(p) {
                var t = new Date(p.date + "T00:00:00").getTime(); return t >= start && t <= end
            })
            var spec = Number(root.deviceController.specFullHours) || 0
            var values = []
            pts.forEach(function(p) { var t = new Date(p.date + "T00:00:00").getTime(); if (t >= start && t <= end) values.push(Number(p.fullHours)) })
            trend.forEach(function(p) { values.push(Number(p.fullHours)) })
            if (spec > 0) values.push(spec)
            values = values.filter(function(v) { return isFinite(v) })
            var rawMin = values.length ? Math.min.apply(null, values) : 0
            var rawMax = values.length ? Math.max.apply(null, values) : 1
            var span = Math.max(4, rawMax - rawMin), pad = span * 0.1
            var low = rawMin - pad, high = rawMax + pad
            var targetStep = (high - low) / 5, power = Math.pow(10, Math.floor(Math.log(targetStep) / Math.LN10))
            var fraction = targetStep / power
            var step = (fraction <= 1 ? 1 : fraction <= 2 ? 2 : fraction <= 5 ? 5 : 10) * power
            var yMin = Math.floor(low / step) * step, yMax = Math.ceil(high / step) * step
            var ticks = Math.round((yMax - yMin) / step)
            if (ticks < 4) { step = Math.max(1, Math.ceil((yMax - yMin) / 5)); yMin = Math.floor(low / step) * step; yMax = Math.ceil(high / step) * step }
            var L = 48, R = 58, T = 10, B = 27, pw = Math.max(1, w - L - R), ph = Math.max(1, h - T - B)
            function X(t) { return L + (t - start) / (end - start) * pw }
            function Y(v) { return T + (yMax - v) / (yMax - yMin) * ph }
            // Grid and axis labels.
            ctx.font = "10px sans-serif"; ctx.textAlign = "right"; ctx.textBaseline = "middle"; ctx.fillStyle = root.txtFaint
            for (let y = yMin; y <= yMax + step * 0.01; y += step) {
                let yy = Y(y); ctx.strokeStyle = root.line; ctx.lineWidth = 1
                ctx.beginPath(); ctx.moveTo(L, yy); ctx.lineTo(w - R, yy); ctx.stroke()
                ctx.fillText(root.tr("battery_axis_hours").arg(Math.round(y)), L - 7, yy)
            }
            // Spec reference.
            if (spec > 0) {
                ctx.save(); ctx.setLineDash([5, 4]); ctx.strokeStyle = root.txtFaint; ctx.lineWidth = 1
                ctx.beginPath(); ctx.moveTo(L, Y(spec)); ctx.lineTo(w - 4, Y(spec)); ctx.stroke(); ctx.restore()
                ctx.font = "10px sans-serif"; ctx.fillStyle = root.txtFaint; ctx.textAlign = "right"; ctx.textBaseline = "bottom"
                ctx.fillText("Sony spec 27 h", w - 4, Y(spec) - 3)
            }
            var radius = pts.length <= 40 ? 4 : pts.length <= 100 ? 3 : 2
            pts.forEach(function(p) {
                var t = new Date(p.date + "T00:00:00").getTime()
                if (t < start || t > end) return
                var x = X(t), y = Y(Number(p.fullHours)); ctx.beginPath(); ctx.arc(x, y, radius, 0, Math.PI * 2)
                if (p.valid) { ctx.fillStyle = root.success; ctx.fill() }
                ctx.strokeStyle = p.valid ? root.success : root.txtFaint; ctx.lineWidth = 1.5; ctx.stroke()
            })
            // Seven-day trend sits over measured points.
            ctx.strokeStyle = root.accent; ctx.lineWidth = 2.5
            var prev = null
            trend.forEach(function(p) {
                var t = new Date(p.date + "T00:00:00").getTime(), v = Number(p.fullHours)
                if (prev && t - prev.t <= dayMs * 1.1) { ctx.beginPath(); ctx.moveTo(X(prev.t), Y(prev.v)); ctx.lineTo(X(t), Y(v)); ctx.stroke() }
                prev = { t: t, v: v }
            })
            // Date-scaled labels. End labels use inward alignment to stay visible.
            var n = Math.min(5, Math.max(2, Math.floor(pw / 105)))
            ctx.font = "10px sans-serif"; ctx.fillStyle = root.txtFaint; ctx.textBaseline = "top"
            for (let i = 0; i < n; i++) {
                let time = start + (end - start) * i / (n - 1), d = new Date(time)
                ctx.textAlign = i === 0 ? "left" : i === n - 1 ? "right" : "center"
                ctx.fillText((d.getMonth() + 1) + "/" + d.getDate(), X(time), h - B + 5)
            }
            // Mouse-selected point ring.
            if (mouse.nearestIndex >= 0) {
                let p = pts[mouse.nearestIndex], t = new Date(p.date + "T00:00:00").getTime()
                if (t >= start && t <= end) {
                    let px = X(t), py = Y(Number(p.fullHours))
                    ctx.beginPath(); ctx.arc(px, py, radius + 3, 0, Math.PI * 2); ctx.strokeStyle = root.accent; ctx.lineWidth = 1.5; ctx.stroke()
                    root.tooltipText = root.tr("battery_history_tip").arg(p.date).arg(Number(p.fullHours).toFixed(1)).arg(Number(p.hours).toFixed(1)).arg(Math.round(Number(p.ancShare) * 100))
                    root.tooltipX = Math.max(2, Math.min(w - tooltip.implicitWidth - 2, px + 10))
                    root.tooltipY = Math.max(2, Math.min(h - tooltip.implicitHeight - 2, py - tooltip.implicitHeight - 8))
                    return
                }
            }
            root.tooltipX = -1000
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            property int nearestIndex: -1
            onPositionChanged: {
                var pts = root.shownDays, best = -1, distance = Infinity
                var today = new Date(); today.setHours(0, 0, 0, 0)
                var start = root.rangeDays >= 99999 ? (pts.length ? new Date(pts[0].date + "T00:00:00").getTime() : 0) : today.getTime() - root.rangeDays * 86400000
                var end = root.rangeDays >= 99999 ? (pts.length ? new Date(pts[pts.length - 1].date + "T00:00:00").getTime() : 0) : today.getTime()
                if (end <= start) end = start + 86400000
                var L = 48, R = 58
                pts.forEach(function(p, i) { var t = new Date(p.date + "T00:00:00").getTime(); var x = L + (t - start) / (end - start) * (width - L - R); var d = Math.abs(mouseX - x); if (t >= start && t <= end && d < distance) { distance = d; best = i } })
                nearestIndex = distance <= 24 ? best : -1
                chart.requestPaint()
            }
            onExited: { nearestIndex = -1; root.tooltipX = -1000; chart.requestPaint() }
        }
        Rectangle {
            id: tooltip
            x: root.tooltipX; y: root.tooltipY
            visible: root.tooltipX >= 0
            z: 2
            radius: 6; color: root.surfaceSunk; border.color: root.line
            implicitWidth: tipText.implicitWidth + 16; implicitHeight: tipText.implicitHeight + 10
            Text { id: tipText; anchors.centerIn: parent; width: Math.min(300, implicitWidth); text: root.tooltipText; color: root.txt; font.pixelSize: 10; textFormat: Text.PlainText }
        }
    }
}
