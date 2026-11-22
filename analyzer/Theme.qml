pragma Singleton
import QtQuick

// Theme : colours, sizes, animation speeds and text formatting, in one place.
// Every other QML file reads them as Theme.something.
QtObject {
    // ---------- light or dark ----------
    property string mode: "auto"          // "auto", "light" or "dark" (saved in the database)
    property bool systemLight: true       // set by Main.qml from the Windows setting
    readonly property bool lightMode: mode === "auto" ? systemLight : mode === "light"

    // ---------- the four greys of the original Main.qml ----------
    readonly property color reallyDark: "#1f1f1f"
    readonly property color dark: "#262626"
    readonly property color reallyLight: "#e7e7e7"
    readonly property color light: "#e0e0e0"

    readonly property color bg: lightMode ? reallyLight : reallyDark      // behind everything
    // cards are lighter than the page in both modes, so they stand out clearly
    readonly property color surface: lightMode ? "#f6f6f6" : "#2c2c2c"     // cards and the sidebar
    readonly property color text: lightMode ? dark : light
    readonly property color muted: lightMode ? "#6a6a6a" : "#a3a3a3"      // secondary text
    readonly property color line: lightMode ? "#c4c4c4" : "#454545"       // borders and grid lines
    readonly property color hover: alpha(text, 0.09)

    // The only colours besides grey: the three states of a muscle.
    readonly property color ok: lightMode ? "#2f7d4f" : "#5fbf86"         // in range
    readonly property color warn: lightMode ? "#a86a12" : "#e0a84a"       // below target
    readonly property color high: lightMode ? "#b3392c" : "#e8776b"       // very high
    readonly property color gold: lightMode ? "#b8860b" : "#f2c14e"       // records, same as on the phone

    readonly property int radius: 8                                        // corner radius, as in the original button

    // ---------- animations ----------
    property bool animations: true
    readonly property int fast: animations ? 140 : 0
    readonly property int normal: animations ? 300 : 0
    readonly property int slow: animations ? 900 : 0

    readonly property var monthNames: ["Jan.", "Feb.", "März", "Apr.", "Mai", "Juni", "Juli", "Aug.", "Sep.", "Okt.", "Nov.", "Dez."]

    // The same colour, see-through. alpha(Theme.text, 0.1) is a faint tint.
    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a)
    }

    // Colours for charts with several parts (stacked bars, rings), in this order.
    // They stay apart in light and dark mode and match the four greys of the app.
    function seriesColor(i) {
        var list = [text, ok, warn, muted, high, gold]
        return list[((i % list.length) + list.length) % list.length]
    }

    // "warn" / "good" / "info" and "under" / "ok" / "high" / "none" / "idle" as a colour.
    function statusColor(status) {
        if (status === "ok" || status === "good") return ok
        if (status === "high") return high
        if (status === "under" || status === "none" || status === "warn") return warn
        return muted
    }

    // 12345.678 -> "12.346" (decimals 0) or "12.345,7" (decimals 1): German style
    function num(value, decimals) {
        var v = Number(value)
        if (isNaN(v)) v = 0
        return v.toLocaleString(Qt.locale("de_DE"), "f", decimals === undefined ? 0 : decimals)
    }

    // A weight in kg as text: "84,0 kg"
    function weight(kg, decimals) {
        return num(kg, decimals === undefined ? 1 : decimals) + " kg"
    }

    // One set as text, the same way the phone shows it: "70 kg × 6", "2 × 20 kg × 10"
    // (two dumbbells), "EG × 9", "EG+10 kg × 5" (EG = Eigengewicht, body weight),
    // timed exercises: "EG · 45 s", "2 × 30 kg · 60 s", "30 min"
    function setLabel(weightKg, reps, loadType, loadMode, unit) {
        var w = num(weightKg, 1).replace(",0", "") + " kg"
        if (loadType === "bodyweight") w = weightKg > 0 ? "EG+" + w : "EG"
        else if (loadType === "assisted") w = "EG−" + w
        else if (loadMode === "perHand") w = "2 × " + w
        if (unit === "seconds" || unit === "minutes") {
            var time = reps + (unit === "seconds" ? " s" : " min")
            return loadType === "external" && !(weightKg > 0) ? time : w + " · " + time
        }
        return w + " × " + reps
    }

    // "2026-11-10" -> "10. Nov."
    function day(iso) {
        if (!iso) return ""
        var p = iso.split("-")
        return parseInt(p[2], 10) + ". " + monthNames[parseInt(p[1], 10) - 1]
    }

    // "2026-11-10" -> "10. Nov. 2026"
    function dayYear(iso) {
        if (!iso) return ""
        return day(iso) + " " + iso.split("-")[0]
    }

    // "2026-11-10" -> a running day number, so dates can be placed on an x axis.
    function dayNumber(iso) {
        var p = iso.split("-")
        return Math.round(Date.UTC(parseInt(p[0], 10), parseInt(p[1], 10) - 1, parseInt(p[2], 10)) / 86400000)
    }

    // 146 seconds -> "2:26"
    function clock(seconds) {
        var s = Math.max(0, Math.round(Number(seconds) || 0))
        var rest = s % 60
        return Math.floor(s / 60) + ":" + (rest < 10 ? "0" : "") + rest
    }

    // 67.4 minutes -> "1 h 07 min", 45 minutes -> "45 min"
    function duration(minutes) {
        var m = Math.max(0, Math.round(Number(minutes) || 0))
        if (m < 60) return m + " min"
        var rest = m % 60
        return Math.floor(m / 60) + " h " + (rest < 10 ? "0" : "") + rest + " min"
    }

    // Numbers next to an axis: 40000 -> "40k", 2.5 -> "2,5", 80 -> "80"
    function axis(value) {
        var v = Math.abs(value)
        if (v >= 10000) return num(value / 1000, value % 1000 === 0 ? 0 : 1) + "k"
        if (Math.abs(value - Math.round(value)) < 0.001) return num(value, 0)
        return num(value, v < 1 ? 2 : 1)
    }

    // The next "round" number above value, used as the top of a bar chart.
    // The steps are chosen so that a quarter of the result is a pleasant number too.
    function niceMax(value) {
        if (!(value > 0)) return 1
        var power = Math.pow(10, Math.floor(Math.log(value) / Math.LN10))
        var n = value / power
        var steps = [1, 1.2, 1.6, 2, 2.4, 3, 4, 5, 6, 8, 10]
        for (var i = 0; i < steps.length; i++) {
            if (n <= steps[i] + 0.000001) return steps[i] * power
        }
        return 10 * power
    }

    // A "round" distance between grid lines for a line chart.
    function niceStep(raw) {
        if (!(raw > 0)) return 1
        var power = Math.pow(10, Math.floor(Math.log(raw) / Math.LN10))
        var n = raw / power
        return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 2.5 ? 2.5 : n <= 5 ? 5 : 10) * power
    }

    // For animations where many things appear one after another.
    // One number "progress" runs from 0 to 1. Item number "index" of "count"
    // starts a little later than the item before it and eases out.
    // Returns that item's own 0 → 1 value.
    function stagger(progress, index, count) {
        var delay = count > 1 ? 0.5 * index / (count - 1) : 0
        var t = Math.max(0, Math.min(1, (progress - delay) / 0.5))
        return 1 - Math.pow(1 - t, 3)
    }
}
