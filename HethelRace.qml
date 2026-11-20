/*****************************************************************************
**  HethelRace.qml  —  Lotus-inspired race cluster for the GARW IC7
**                     (SINGLE-FILE build, derived from the GTDash template)
**
**  Styling takes its cues from the Emira (Track-mode arched rev bar, big gear
**  in a chamfered shield) and the Evora (yellow-on-green, driver-first layout):
**
**     * an arched, wedge-shaped REV BAR across the top — green -> Lotus yellow
**       -> red — with a white-hot leading edge, a fading comet tail when the
**       revs drop, and a tell-tale marker that holds the peak of each rev.
**       REV BAR COLOURS picks ZONES (GREEN / YELLOW / RED FROM rpm, as RaceX),
**       BLEND or ACCENT
**     * a large GEAR digit in the centre shield that "pops" on every shift and
**       pulses red at the shift point
**     * SPEED big under the gear, live RPM on the left wing (RPM/SPEED SWAP
**       flips them) and a selectable RIGHT WING slot: 0-60 timer, fuel %,
**       max speed, max rpm, session timer, peak g, a logo image
**       (assets/wing_logo.png — replace the placeholder with your own) or off
**     * race animations, each with an FX: on/off row in the menu — sequential
**       LED shift lights, edge shift strobe, gear roll,
**       redline bloom, limiter stutter, launch band, accel/brake bar, speed
**       streaks, new-best flash, RACE-mode takeover, critical warning banner,
**       cold-oil rev ceiling, shutdown sweep
**     * four side gauges (oil pressure / oil temp / AFR / coolant) that slide
**       in on power-up and pulse red on an engine-damage critical
**     * battery, fuel, telltales, ECU text line, ODO/TRIP and the optional
**       RACE / SPORT buttons along the bottom
**
**  Gauge + settings menu in one component. Pure QtQuick 2 core (no
**  QtGraphicalEffects / Controls) so it stays portable to the IC7's Qt 5.12.
**  Telltale icons are PNGs in assets/.
**
**  The accent (RED / GREEN / BLUE settings) defaults to Lotus yellow
**  255/224/0. The background tint (BG RED / GREEN / BLUE) defaults to Lotus
**  green 0/120/74. The green used for bar fills and the rev-bar zone is fixed.
**  THEME switches DARK / LIGHT (dark text on a near-white background) / SUNSET
**  (fixed neon-dusk palette: striped sun, palms, star shift lights, red/blue strobe)
**  / CITY MAP (same palette on a night street-map backdrop with card-style panels).
**
**     Up                  open the settings menu
**     Left / Right        move between settings
**     Up / Down           change the selected value (hold to ramp)
**     EXIT row + Up       save to the resolved config path (see cfgCandidates) & close
**
**  D-pad read from rpmtest.inputsdata (udp_packetdata fallback):
**     up 0x20  down 0x2000  left 0x20000000  right 0x40000000
**  While the menu is open, rpmtest.settings_on_offdata is set to 1.
**
**  Settings file: screen_configs/hethelrace_config.txt (key=value lines).
**  Stored but with no visual effect: FUEL HIGH.
**
** ===========================================================================
**  IC7 HARDWARE NOTES  (inherited from GTDash — the desktop sim hides these)
** ===========================================================================
**  1. FONTS — the IC7's Qt does NOT alias the generic "sans-serif" to a sans
**     font; it falls back to a SERIF. Bundle a TTF and load it with FontLoader
**     (uiFontR/uiFontB + the `ff` / `menuFont` properties). Repaint the canvas
**     when the font loads.
**
**  2. INPUT — some IC7 backends update rpmtest.inputsdata WITHOUT emitting a
**     property-change signal, so evalEdges() is also POLLED on a Timer.
**
**  3. CANVAS arcTo IS UNRELIABLE on the IC7's Qt 5.12 paint engine. This dash's
**     canvas uses only moveTo/lineTo polygons, fillRect and plain arc().
**
**  4. PERFORMANCE — Canvas is CPU-rasterised, the expensive path on the IC7.
**     There is ONE canvas (`bg`), full-screen, painted ONCE: backdrop, hex
**     weave, unlit rev-bar segments, scale numbers, gear shield. It repaints
**     only when RPM LIMIT / the red start / HIDE TACH NUMS / the accent / the
**     background tint change.
**     EVERYTHING that moves is scene-graph geometry composited on the GPU:
**       * rev bar  — a Repeater of rotated Rectangles (one per 100 rpm) lit by
**                    the integer `litIndex`, so segment bindings re-evaluate
**                    only when the revs cross a segment, not every frame.
**       * readouts — Text/Rectangle nodes bound to their values.
**     Every animation is EVENT-DRIVEN (power-on, gear change, rev drop, a
**     warning becoming active). A steady-cruising dash animates nothing.
**
**  5. CONFIG FILE — IC7 FileIO quirks, handled in loadConfig/saveConfig:
**     (a) READ is one-line-per-open (see rline()).
**     (b) FileIO does NOT create the file on a read; seed defaults on first
**         run with a SINGLE writetoopenfile() call.
**
**  6. RESOLUTION — the layout is a fixed 800x480.
** ===========================================================================
*****************************************************************************/
import QtQuick 2.7
import FileIO 1.0

Item {
    id: root
    width: 800; height: 480

    // ---- data interface (real rpmtest field names, dot-notation) ----------
    property var d: (typeof rpmtest !== 'undefined') ? rpmtest : null
    property real rpm:       d ? d.rpmdata          : 0
    property real speed:     d ? d.speeddata        : 0      // km/h
    property real peakRpm:   0      // session high-water marks (PEAK card); in-memory,
    property real peakSpeed: 0      // km/h canonical -> reset on power cycle
    property real peakOilTemp:     -1e9   // session max, C canonical
    property real peakCoolant:     -1e9   // session max, C canonical
    property real peakOilPressMax: -1e9   // session max, PSI canonical
    property real peakOilPressMin:  1e9   // session min, PSI canonical (low oil press = danger)
    property real peakAfrMax:      -1e9   // session max, AFR canonical (leanest)
    property real peakAfrMin:       1e9   // session min, AFR canonical (richest)
    onSpeedChanged:     if (speed     > peakSpeed)   peakSpeed   = speed
    onOiltempChanged:   if (oiltemp   > peakOilTemp) peakOilTemp = oiltemp
    onWatertempChanged: if (watertemp > peakCoolant) peakCoolant = watertemp
    onAfrChanged:       { if (afr > peakAfrMax) peakAfrMax = afr;
                          if (afr < peakAfrMin) peakAfrMin = afr; }
    function resetPeaks() {
        peakRpm = 0; peakSpeed = 0;
        peakOilTemp = -1e9; peakCoolant = -1e9;
        peakOilPressMax = -1e9; peakOilPressMin = 1e9;
        peakAfrMax = -1e9; peakAfrMin = 1e9;
        peakGAcc = 0; peakGBrk = 0; accLast = 0; accBest = 0; maxPrev = 0;
        settingsRev += 1;
    }
    property int  gearpos:   d ? d.geardata         : 0
    property real watertemp: d ? d.watertempdata    : 0      // °C
    property real fuel:      d ? d.fueldata         : 0      // 0..100 %
    property real odometer:  d ? (d.odometer0data    / 10) : 0   // tenths of km
    property int  tripmeter: d ? (d.tripmileage0data / 10) : 0   // tenths of km
    property int  inputs:    d ? d.inputsdata       : 0
    // ECU ASCII status text over CAN (e.g. "TPMS Fault", "Slip %"). Host may send
    // it as a string or a NUL-terminated byte array; decode both. The raw read is
    // a binding so it stays reactive; absent in the sim -> "" (line stays hidden).
    // Read as a QML string so the host QByteArray/QString is coerced cleanly (the
    // reference dash does the same). Then sanitise: keep printable ASCII up to the
    // first NUL and trim. This drops the stray control/padding bytes that render as
    // boxes ("[]") while a multi-frame ECU message is still streaming in.
    // ECU ASCII status text (CAN canasciidata), shown raw. Read as a QML string
    // so the host value is coerced cleanly, then drop control / non-printable
    // bytes (which would render as boxes) and trim the ends — without truncating
    // at NULs. No buffering, assembly or rate-limiting: the line always reflects
    // exactly the current value the ECU is sending, and clears when it clears.
    property string canAsciiRaw: d ? d.canasciidata : ""
    readonly property string canAsciiStr: {
        var src = root.canAsciiRaw;
        if (!src) return "";
        var out = "";
        for (var i = 0; i < src.length; i++) {
            var c = src.charCodeAt(i);
            if (c >= 32 && c < 127) out += src.charAt(i);   // keep printable ASCII; drop NUL/control/high bytes
        }
        return root.canAsciiCollapse(out.trim());
    }
    // True if b is the same characters as a in a rotated order once spaces are
    // removed (b is a rotation of a). Recognises a no-separator repeat that the
    // collapse reordered ("7% Slip" vs "Slip7%", "LTC Off" vs "OffLTC") so the
    // display can hold the version already shown instead of flipping to the garble.
    function canAsciiSameRotation(a, b) {
        // a = fresh candidate, b = the text already on screen. Only treat a as
        // a garbled rotation of b when a has NO separator but b DOES -- i.e. a
        // is the space-stripped, reordered repeat ("Slip7%" of "7% Slip"). Two
        // distinct single words that happen to be rotations (STOP/POST) both
        // lack spaces and so are left alone (hardened residual-risk guard).
        if (a.indexOf(" ") >= 0 || b.indexOf(" ") < 0) return false;
        var x = a.split(" ").join(""), y = b.split(" ").join("");
        if (!x.length || x.length !== y.length || x === y) return false;
        return (x + x).indexOf(y) >= 0;
    }
    // Message severity: faults outrank info. Drives BOTH the min-dwell and the
    // severity-hold gate in canAsciiSettle (one notion, no separate priority).
    function canAsciiSeverity(s) {
        if (!s) return 0;                                   // blank
        return (s.indexOf("FAULT") >= 0 || s === "TPMS") ? 2 : 1;   // 2 = fault-class, 1 = info
    }
    // Collapse a host buffer that does not self-clear and piles a message up.
    // Word-level only: drop word-fragments left by a window that opened or closed
    // mid-word, drop consecutive duplicate words, then collapse an exact repeated
    // phrase to one copy. Distinct messages ("TPMS FAULT", "Boost Control Fault
    // Detected") have no such repeat and pass through untouched.
    // NOTE: a char-level "smallest period" collapse was tried and removed -- it
    // mangled FAULT. Do NOT reintroduce it.
    function canAsciiCollapse(out) {
        if (!out.length) return "";
        var w = out.split(/\s+/);
        // The host window can open or close mid-word, so the first token may be a
        // SUFFIX of the real word ("AULT FAULT", "T FAULT", "ULT FAULT") and the
        // last token a PREFIX of it ("FAULT FAU", "LT FAULT FAU"). Drop those
        // partials. (substring, not endsWith/startsWith, for Qt 5.12.8 V4 safety.)
        if (w.length >= 2) {
            var f = w[0], s = w[1];
            if (f.length < s.length && s.substring(s.length - f.length) === f) w.shift();
        }
        if (w.length >= 2) {
            var e = w[w.length - 1], q = w[w.length - 2];
            if (e.length < q.length && q.substring(0, e.length) === e) w.pop();
        }
        var c = [];                                                // collapse consecutive duplicate words
        for (var a = 0; a < w.length; a++)
            if (a === 0 || w[a] !== w[a - 1]) c.push(w[a]);
        var n = c.length;                                          // collapse an exact repeated phrase
        for (var pp = 1; pp <= (n >> 1); pp++) {
            if (n % pp !== 0) continue;
            var rep = true;
            for (var j = pp; j < n; j++) { if (c[j] !== c[j - pp]) { rep = false; break; } }
            if (rep) return c.slice(0, pp).join(" ");
        }
        return c.join(" ");
    }
    property real oiltemp:   d ? d.oiltempdata      : 0      // °C (native)
    property real oilpress:  d ? (d.oilpressuredata * 14.5038) : 0  // native BAR -> PSI (canonical)
    // Smoothed oil-pressure display: sweeps up from 0 as the engine builds
    // pressure on start (and eases down on shut-off) instead of snapping.
    property real oilPressShown: 0
    Behavior on oilPressShown { SmoothedAnimation { velocity: 60 } }   // ~PSI/sec
    onOilpressChanged: { oilPressShown = oilpress;
                         if (oilpress > peakOilPressMax) peakOilPressMax = oilpress;
                         if (oilpress < peakOilPressMin) peakOilPressMin = oilpress; }
    property real afr:       d ? (d.o2data * 14.7)  : 0      // native lambda -> AFR (canonical, x14.7)
    property real battery:   d ? d.batteryvoltagedata : 0    // volts
    property real batteryShown: 0   // debounced volts actually shown (see battery throttle timer)

    // =======================================================================
    //  SETTABLE CONFIG  (the menu writes these directly; persisted to disk)
    // =======================================================================
    // --- engine / tach ---
    property int  rpmredline: 7000     // SHIFT RPM  (tach turns red above this)
    property int  rpmmax:     9000     // RPM LIMIT  (full-scale rpm)
    property int  rpmDamp:    3        // RPM DAMPING (1 = snappy ... 10 = smooth)

    // --- rev bar colours (as RaceX): ZONES = accent below GREEN FROM, then green,
    //     yellow from YELLOW FROM, red from RED FROM. BLEND = green fading into the
    //     accent, red at SHIFT RPM. ACCENT = accent colour, red at SHIFT RPM.
    property int  barColours: 1        // 0 = ACCENT, 1 = ZONES, 2 = BLEND
    property int  greenFrom:  0        // rpm
    property int  yellowFrom: 6000     // rpm
    property int  redFrom:    7000     // rpm
    // rpm where the bar (and its scale numbers) turn red
    readonly property int revRedStart: barColours === 1 ? redFrom : rpmredline

    // --- race animations (each has an FX: row in the menu; all event-driven) ---
    property bool fxSeq:      true     // sequential LED shift lights (replace the three rings)
    property bool fxEdge:     true     // screen-edge strobe at the shift point
    property bool fxRoll:     true     // gear digit rolls up / down on a shift (off = pop)
    property bool fxBloom:    true     // glow widens in the red zone
    property bool fxLimiter:  true     // last segments stutter at RPM LIMIT
    property bool fxLaunch:   true     // launch target band when stationary with revs up
    property bool fxAccel:    true     // accel / brake bar under the big readout
    property bool fxStreaks:  true     // speed streaks in the wings
    property bool fxBest:     true     // MAX readout flashes + counts up on a new best
    property bool fxRace:     true     // RACE input: gauges shrink, gear + bar grow
    property bool fxBanner:   true     // critical warning banner across the centre
    property bool fxCold:     true     // blue cold-oil rev ceiling on the bar
    property bool fxShutdown: true     // gauges slide out and back when the engine stops
    readonly property var fxKeys: ["fxSeq","fxEdge","fxRoll","fxBloom","fxLimiter","fxLaunch",
                                   "fxAccel","fxStreaks","fxBest","fxRace","fxBanner","fxCold","fxShutdown"]
    property int  launchRpm:  4000     // LAUNCH RPM: centre of the launch target band (+/-300)

    // --- RIGHT WING: what the slot right of the gear shows ---
    //     0 = 0-100 km/h (0-60 mph) timer, 1 = fuel %, 2 = max speed, 3 = max rpm,
    //     4 = session timer, 5 = peak g, 6 = logo image (assets/wing_logo.png), 7 = off
    property int  rightWing: 0
    // LOGO TINT: recolour the logo image so single-colour artwork stays visible on
    // either theme. 0 = OFF (image as supplied), 1 = THEME (text colour: white on
    // DARK, near-black on LIGHT), 2 = ACCENT. Uses the image's transparency only.
    property int  logoTint: 0
    readonly property var rightWingNames: ["0-60 TIMER", "FUEL %", "MAX SPEED", "MAX RPM", "SESSION", "PEAK G", "LOGO", "OFF"]

    // 0-100 km/h (0-60 mph when SPEED UNIT is MPH) timer. Arms at a standstill,
    // starts when the car moves, stops at the target speed; the last time stays
    // up until the next run. Polled (50 ms) so it works without change signals.
    readonly property real accTarget: speedunits === 0 ? 100 : 60 * 1.609     // km/h
    property int  accState: 0          // 0 = waiting for a standstill, 1 = armed, 2 = running, 3 = done
    property real accT0:   0           // ms timestamp of the start
    property real accNow:  0           // running time, s (tenths)
    property real accLast: 0           // last completed run, s
    property real accBest: 0           // best run this session, s
    Timer {
        interval: 50; repeat: true; running: root.rightWing === 0 && !root.selfTest
        onTriggered: {
            var sp = root.speed, now = Date.now();
            if (root.accState === 2) {
                var e = (now - root.accT0) / 1000;
                if (sp >= root.accTarget) {
                    root.accLast = e; root.accState = 3;
                    if (root.accBest <= 0 || e < root.accBest) { root.accBest = e; if (root.fxBest) bestAnim.restart(); }
                } else if (sp < 1)  root.accState = 1;          // stopped again: re-arm
                else if (e > 60)    root.accState = 0;          // not a timed run
                else { var t = Math.floor(e * 10) / 10; if (t !== root.accNow) root.accNow = t; }
            } else if (sp < 1) { if (root.accState !== 1) root.accState = 1; }
            else if (root.accState === 1) { root.accT0 = now; root.accNow = 0; root.accState = 2; }
        }
    }

    // session timer: engine-running time since power-on
    property int sessionSec: 0
    Timer { interval: 1000; repeat: true; running: !root.engineOff && !root.selfTest; onTriggered: root.sessionSec += 1 }
    function fmtSession(t) {
        var m = Math.floor(t / 60), sec = t % 60;
        if (m < 100) return m + ":" + (sec < 10 ? "0" : "") + sec;                 // m:ss
        return Math.floor(m / 60) + "h" + (m % 60 < 10 ? "0" : "") + (m % 60);      // 1h45
    }

    // peak g: hardest acceleration / braking this session (from the accel bar's g)
    property real peakGAcc: 0
    property real peakGBrk: 0
    onAccelGChanged: { if (accelG > peakGAcc) peakGAcc = accelG; if (-accelG > peakGBrk) peakGBrk = -accelG; }

    // --- colour scheme: the accent is built from RGB ---
    property int  red:   255           // default 255/224/0 == Lotus yellow #ffe000
    property int  green: 224
    property int  blue:  0

    // --- background tint: every dark background / panel / border shade is derived
    //     from this colour (BG RED / GREEN / BLUE). Default 0/120/74 = Lotus green.
    //     0/0/0 gives a neutral carbon-grey dash.
    property int  bgRed:   0
    property int  bgGreen: 120
    property int  bgBlue:  74
    // --- THEME: 0 = DARK (light text on a dark tinted background), 2 = SUNSET (see
    //     `sunset` below), 1 = LIGHT
    //     (dark text on a near-white background; BG 255/255/255 = pure white).
    property int  theme: 0
    readonly property bool   light: theme === 1
    readonly property bool   sunset: theme >= 2       // neon themes (SUNSET, CITY MAP): fixed palette, stars, police strobe
    readonly property bool   mapBg:  theme === 3      // CITY MAP: night street-map backdrop + card-style panels
    readonly property string outlineCol: mapBg ? "#0b1230" : "#2a0f5c"
    // effective accent / background tint: the RGB settings, except in SUNSET
    readonly property int aR: sunset ? 255 : red
    readonly property int aG: sunset ? 79  : green
    readonly property int aB: sunset ? 176 : blue
    readonly property int tR: mapBg ? 55  : (sunset ? 150 : bgRed)
    readonly property int tG: mapBg ? 85  : (sunset ? 50  : bgGreen)
    readonly property int tB: mapBg ? 200 : (sunset ? 235 : bgBlue)
    readonly property string fg:        light ? "#0b1510" : "#ffffff"     // primary readouts
    readonly property string fg2:       light ? "#24332c" : "#dbeee4"     // secondary text
    readonly property string fgDim:     light ? "#4d6b5e" : "#8fb5a3"     // units / hints
    readonly property string accentInk: light ? ("#" + hx(aR * 0.55) + hx(aG * 0.55) + hx(aB * 0.55)) : accent   // accent for text + thin lines
    readonly property string greenInk:  light ? "#0c8a48" : lotusGreen
    readonly property string redSoft:   light ? "#c81414" : "#ff7777"
    // shade of the tint. DARK: channel = tint * k + lift (lift = neutral grey floor).
    // LIGHT: the same role mapped onto white — white pulled toward the tint by k,
    // then darkened a little so borders / panels stay visible on a white tint.
    function bgC(c, k, lift) { return light ? (255 - (255 - c) * k * 0.9 - lift * 0.6 - k * 60) : (c * k + lift); }
    function bgS(k, lift) { return "#" + hx(bgC(tR, k, lift)) + hx(bgC(tG, k, lift)) + hx(bgC(tB, k, lift)); }
    function bgA(k, lift, a) {      // CSS rgba() string for the Canvas (centre glow: lift 0; hex weave: lift > 0)
        function c(v) { return Math.max(0, Math.min(255, Math.round(v))); }
        if (light) {
            var m = lift > 0 ? 0.5 : 1.0, al = lift > 0 ? a * 1.5 : a * 0.45;
            return "rgba(" + c(tR * m) + "," + c(tG * m) + "," + c(tB * m) + "," + Number(al).toFixed(3) + ")";
        }
        return "rgba(" + c(tR * k + lift) + "," + c(tG * k + lift) + "," + c(tB * k + lift) + "," + Number(a).toFixed(3) + ")";
    }
    readonly property color bgPanel: Qt.rgba(Math.max(0, bgC(tR, 0.158, 7)) / 255, Math.max(0, bgC(tG, 0.158, 7)) / 255,
                                             Math.max(0, bgC(tB, 0.158, 7)) / 255, mapBg ? 0.93 : 0.84)
    readonly property int   bgKey: bgRed * 65536 + bgGreen * 256 + bgBlue + theme * 16777216

    // --- units ---
    property int  speedunits: 0        // 0 = km/h, 1 = mph
    property int  distunits:  0        // 0 = km,   1 = miles (odometer + trip)
    property int  tempunits:  0        // coolant 0 = °C, 1 = °F

    // --- bar-gauge ranges ---
    property real coolantHigh:   110   // °C (canonical) — coolant turns red at/above
    property real coolantLow:    60    // °C (canonical)
    property int  fuelHigh:      90
    property int  fuelLow:       15    // % — fuel bar turns red below this
    property int  fuelDamp:      3
    property real oilTempHigh:   130   // °C (canonical)
    property real oilTempLow:    80    // °C (canonical)
    property int  oilTempUnits:  0     // 0 = °C, 1 = °F, 2 = OFF (blank)
    property real oilPressHigh:  90    // PSI (canonical)
    property real oilPressLow:   15    // PSI (canonical)
    property int  oilPressUnits: 1     // 0 = PSI, 1 = BAR, 2 = OFF  (sensor native BAR)
    property real batteryHigh:   14.8
    property real batteryLow:    11.8
    property real afrHigh:       1.02   // O2 limits stored in LAMBDA (1.02 = 15.0 AFR)
    property real afrLow:        0.82   //                            (0.82 = 12.0 AFR)
    property int  afrSource:     1     // O2 DISPLAY: 0 = AFR, 1 = LAMBDA, 2 = OFF
                                       // (o2data is native lambda -> afr is canonical AFR)
    // afr is canonical AFR; afrShown converts it to the selected display unit
    readonly property real afrShown: afrSource === 1 ? afr / 14.7   // LAMBDA
                                   : afr                            // AFR  (OFF hides the gauge)

    // Each unit/source setting has an OFF state (the highest value) that hides
    // that side gauge entirely — both its panel box (static layer) and its live
    // content (dynamic layer): oil-temp/oil-press/coolant OFF=2, AFR OFF=3.
    readonly property bool showOilTemp:  oilTempUnits  <= 1                 // °C/°F only; OFF(2) blank
    readonly property bool showOilPress: oilPressUnits !== 2
    readonly property bool showCoolant:  tempunits     !== 2
    readonly property bool showAfr:      afrSource     !== 2
    readonly property bool showPeak:     showPeakGauge                       // PEAK card occupies a chosen corner slot
    property bool showPeakGauge:     false  // SHOW PEAK GAUGE menu toggle (default off)
    property int  peakGaugePosition: 1      // PEAK POSITION: 1=top-left 2=top-right 3=bottom-left 4=bottom-right
    // which metrics the PEAK card lists (default RPM+SPEED = original behaviour)
    property bool peakShowRpm:      true
    property bool peakShowSpeed:    true
    property bool peakShowAfr:      false
    property bool peakShowOilTemp:  false
    property bool peakShowOilPress: false
    property bool peakShowCoolant:  false
    // {label,text} per enabled metric, converted to the user's units at read time
    readonly property var peakRows: {
        var a = [];
        var rpmRow = { label: "RPM", text: String(Math.round(peakRpm)) };
        var spdRow = { label: (speedunits === 0 ? "KM/H" : "MPH"),
                       text: String(Math.round(speedunits === 0 ? peakSpeed : peakSpeed / 1.609)) };
        if (placementSwap) { if (peakShowSpeed) a.push(spdRow); if (peakShowRpm) a.push(rpmRow); }
        else               { if (peakShowRpm) a.push(rpmRow); if (peakShowSpeed) a.push(spdRow); }
        if (peakShowAfr)      a.push({ label: (afrSource === 1 ? "\u03BB" : "AFR"),
                                       text: peakFmtAfr(peakAfrMin) + "\u2013" + peakFmtAfr(peakAfrMax) });
        if (peakShowOilTemp)  a.push({ label: "OIL T", text: peakFmtTemp(peakOilTemp, oilTempUnits) });
        if (peakShowOilPress) a.push({ label: "OIL P", text: peakFmtPressRange(peakOilPressMin, peakOilPressMax) });
        if (peakShowCoolant)  a.push({ label: "COOL",  text: peakFmtTemp(peakCoolant, tempunits) });
        return a;
    }
    readonly property int peakRowH: Math.max(9, Math.min(24, Math.floor((54 - (Math.max(1, peakRows.length) - 1)) / Math.max(1, peakRows.length))))
    readonly property int peakMaxVal: { var m = 1; for (var i = 0; i < peakRows.length; i++) m = Math.max(m, peakRows[i].text.length);  return m; }
    readonly property int peakMaxLab: { var m = 1; for (var j = 0; j < peakRows.length; j++) m = Math.max(m, peakRows[j].label.length); return m; }
    // ONE uniform font for the whole card: the largest that fits the row height
    // and the longest label/value, so every row matches (no per-cell shrink)
    readonly property int peakFont: Math.max(9, Math.min(20, peakRowH - 2,
                                     Math.floor(84 / (peakMaxVal * 0.60)),
                                     Math.floor(58 / (peakMaxLab * 0.60))))
    // vertically centre the list in the space under the PEAK header
    readonly property int peakColY: Math.round(25 + Math.max(0,
                                     (54 - (peakRows.length * peakRowH + Math.max(0, peakRows.length - 1))) / 2))
    function peakFmtTemp(c, units) {
        if (c <= -1e8) return "--";
        return String(Math.round(units === 1 ? c * 9/5 + 32 : c)) + (units === 1 ? "\u00B0F" : "\u00B0C");
    }
    function peakFmtPressRange(lo, hi) {
        if (hi <= -1e8) return "--";
        if (oilPressUnits === 0) return String(Math.round(lo)) + "\u2013" + String(Math.round(hi)) + " PSI";
        return (lo / 14.5038).toFixed(1) + "\u2013" + (hi / 14.5038).toFixed(1) + " BAR";
    }
    function peakFmtAfr(a) {
        if (a <= -1e8 || a >= 1e8) return "--";
        return afrSource === 1 ? (a / 14.7).toFixed(2) : a.toFixed(1);
    }
    // peak-card corner coordinates + which corner gauge the card displaces
    readonly property real peakX: (peakGaugePosition === 2 || peakGaugePosition === 4) ? 612 : 12
    readonly property real peakY: (peakGaugePosition === 1 || peakGaugePosition === 2) ? 184 : 276
    readonly property bool peakAtOilPress: showPeak && peakGaugePosition === 1
    readonly property bool peakAtAfr:      showPeak && peakGaugePosition === 2
    readonly property bool peakAtOilTemp:  showPeak && peakGaugePosition === 3
    readonly property bool peakAtCoolant:  showPeak && peakGaugePosition === 4
    function peakOccupies(k) {
        return (k === "oilpress" && peakAtOilPress) || (k === "afr"     && peakAtAfr)
            || (k === "oiltemp"  && peakAtOilTemp)  || (k === "coolant" && peakAtCoolant);
    }

    // --- display ---
    property int  nightlight: 0        // 0..100 night dimmer (0 = off)

    // accent colour assembled from the RGB scheme (CSS hex for the Canvas)
    function hx(n) { n = Math.max(0, Math.min(255, Math.round(n))); var s = n.toString(16); return (s.length < 2 ? "0" : "") + s; }
    readonly property string accent: "#" + hx(aR) + hx(aG) + hx(aB)
    // rpm-needle smoothing. The spring chases rpmDisplay toward the live rpm.
    // RPM DAMPING 1..10 sets the rpm-needle spring stiffness: 1 = snappiest
    // (tracks a throttle blip tightly), 10 = a calm, lazy gliding needle.
    // Geometric scale — each step multiplies stiffness by a constant ratio
    // (~0.63), so the *perceived* change is even across 1..10 instead of
    // bunching at the stiff end. Measured settle (step to 5000 rpm, to within
    // 2%), desktop sim — approximate, confirm feel on hardware:
    //    damp  spring  settle        damp  spring  settle
    //     1     55.0   ~25 ms         6      5.2   ~175 ms
    //     2     34.4   ~50 ms         7      3.3   ~300 ms
    //     3*    21.5   ~75 ms         8      2.0   ~475 ms
    //     4     13.4   ~100 ms        9      1.3   ~900 ms
    //     5      8.4   ~150 ms        10     0.8   ~1400 ms
    //   (* = default)
    readonly property real springVal: 55.0 * Math.pow(0.8 / 55.0, (Math.max(1, Math.min(10, rpmDamp)) - 1) / 9.0)

    // ---- bundled UI font ---------------------------------------------------
    // The IC7's Qt does not alias the generic "sans-serif" to a sans font (it
    // falls back to a serif), so we ship DejaVu Sans and use it explicitly.
    FontLoader { id: uiFontR; source: "assets/DejaVuSans.ttf"
        onStatusChanged: if (status === FontLoader.Ready) root.fontsReady() }
    // display face for the neon themes (NEON FONT setting). Used only for text made
    // of digits / A-Z / basic punctuation, which it covers; everything else (units
    // with a degree sign or lambda, icons, the menu rows) stays in DejaVu.
    FontLoader { id: uiFontD; source: "assets/pricedown.ttf" }
    property bool neonFont: true
    readonly property bool   dispOn:   sunset && neonFont && uiFontD.status === FontLoader.Ready
    readonly property string dispFont: dispOn ? uiFontD.name : menuFont
    readonly property bool   dispBold: !dispOn          // single-weight face: no synthetic bold
    FontLoader { id: uiFontB; source: "assets/DejaVuSans-Bold.ttf"
        onStatusChanged: if (status === FontLoader.Ready) root.fontsReady() }
    // quoted family name for Canvas ctx.font; falls back until the font loads
    readonly property string ff: (uiFontR.status === FontLoader.Ready)
                                 ? ('"' + uiFontR.name + '"') : "sans-serif"
    // unquoted family name for QML Text elements (the ListView menu)
    readonly property string menuFont: (uiFontR.status === FontLoader.Ready)
                                       ? uiFontR.name : "sans-serif"
    function fontsReady() {
        if (typeof bg !== 'undefined') bg.requestPaint();
        // (the tach, readout layer and ListView menu are all item-based; their
        //  bindings re-render on their own when menuFont changes as the font
        //  loads — bg is the only canvas, so it is the only manual repaint)
    }

    // ---- decoded telltales (inputsdata bits) ------------------------------
    property bool tRace:     inputs & 0x800000
    property bool tSport:    inputs & 0x1000000
    property bool tLeft:     inputs & 0x40
    property bool tRight:    inputs & 0x80
    // The raw turn bits above track the car's flasher relay (i.e. the actual bulb).
    // Mirror that state directly so the dash telltale lights and darkens in sync
    // with the bulb. It's refreshed each 50 ms by the input poll below (the same
    // path the D-pad uses, robust on backends that don't emit change signals). No
    // dash-side blink timer is applied here, so there is only one blinker (the
    // relay) -- that both keeps them in phase and avoids the earlier beat that
    // dropped blinks.
    property bool tLeftActive:  false
    property bool tRightActive: false

    // ---- spring-damped rpm + animation clock ------------------------------
    property real rpmDisplay: 0
    // damping 0.55 settles fast with little overshoot (was 0.30 = bouncy/slow).
    readonly property real springDamp: 0.30 + springVal * 0.025   // paired to the stiffness: clean settle, ~no bounce across the range
    Behavior on rpmDisplay { SpringAnimation { spring: root.springVal; damping: root.springDamp; epsilon: 1 } }
    onRpmChanged: { rpmDisplay = rpm; if (rpm > peakRpm) peakRpm = rpm; }

    // ---- power-on self-test sweep ------------------------------------------
    //  On boot, sweep the tach 0 -> max -> 0 while every telltale and shift
    //  light is lit, then hand over to live data. `selfTest` gates the readouts
    //  so the sweep value (not the engine-off placeholder) is shown. rpmShown is
    //  what the tach, rpm number and shift lights read.
    property bool  selfTest: true
    property real  sweepRpm: 0
    property real  settle:   0   // 0 = showing the swept value, 1 = eased onto live
    // during the test the tach sweeps up, then eases from the peak onto the live
    // value so nothing snaps when the test hands over to real data
    readonly property real rpmShown: selfTest ? (sweepRpm * (1 - settle) + rpmDisplay * settle) : rpmDisplay
    // 0..1 sweep progress; drives every bar during the power-on self-test
    readonly property real sweepFrac: Math.max(0, Math.min(1, sweepRpm / Math.max(1, rpmmax)))
    SequentialAnimation {
        id: bootSweep; running: false
        // sweep the tach + every bar up to full
        NumberAnimation { target: root; property: "sweepRpm"; from: 0; to: root.rpmmax; duration: 850; easing.type: Easing.OutCubic }
        PauseAnimation  { duration: 200 }
        // then ease everything from full down onto the real live values (no snap)
        NumberAnimation { target: root; property: "settle";   from: 0; to: 1;            duration: 700; easing.type: Easing.InOutCubic }
        ScriptAction    { script: root.selfTest = false }
    }

    // ---- fuel-bar damping --------------------------------------------------
    //  Tank fuel sloshes under cornering / braking / hills, so the bar is eased
    //  toward the live reading with a velocity limit: rapid slosh averages out
    //  because the bar can only move so fast and the transient targets cancel.
    //  FUEL DAMP 0 = raw/instant; 1 = light (settles in ~1-2s) ... 9 = heavy
    //  (slow glide, ~8-10s, ignores transient slosh). fuelLevel is what every
    //  fuel readout reads (bar fill, low-fuel colour, pump telltale).
    readonly property real fuelVel: Math.max(8.0, 75.0 - (fuelDamp - 1) * 8.0)   // %/sec for damp 1..9
    property real fuelDisplay: 0
    Behavior on fuelDisplay { SmoothedAnimation { velocity: root.fuelVel } }
    // ---- trimmed-mean (median-window) fuel filter --------------------------
    //  Ring buffer of raw samples, sorted each tick; only the CENTER slice is
    //  averaged, so slosh spikes/dropouts sort to the ends and get discarded
    //  (no matching opposite transient needed to cancel them). fuelDamp sets the
    //  window: 0 = raw/off, 1 -> 6 samples (~1.5s) ... 9 -> 30 (~7.5s). The
    //  filtered value feeds the smooth glide above.
    property var  fuelBuf: []
    readonly property int fuelWin: (fuelDamp <= 0) ? 1 : (3 + fuelDamp * 3)
    property real fuelFiltered: 0
    // Sample straight from the firmware when it is there: some IC7 builds update
    // fueldata without a change signal, which would leave the `fuel` binding stale
    // (same refinement as RaceX's FuelFilter).
    function fuelNow() {
        if (root.d && root.d.fueldata !== undefined) {
            var v = Number(root.d.fueldata);
            if (!isNaN(v)) return v;
        }
        return root.fuel;
    }
    function fuelSampleTick() {
        if (fuelDamp <= 0) return;                             // raw mode: filter idle
        var b = root.fuelBuf;
        b.push(root.fuelNow());
        while (b.length > root.fuelWin) b.shift();
        root.fuelBuf = b;
        var n = b.length;
        var a = b.slice().sort(function(x, y){ return x - y; });
        var center = Math.max(1, Math.round(n * 0.4));   // keep ~40% of the window
        var trim = Math.floor((n - center) / 2);         // drop the low/high ends
        var sum = 0, cnt = 0;
        for (var i = trim; i < n - trim; i++) { sum += a[i]; cnt++; }
        root.fuelFiltered = cnt > 0 ? sum / cnt : a[Math.floor(n / 2)];
    }
    Timer { interval: 250; repeat: true; running: root.fuelDamp > 0; onTriggered: root.fuelSampleTick() }
    onFuelFilteredChanged: fuelDisplay = fuelFiltered
    readonly property real fuelLevel: (fuelDamp <= 0) ? fuel : fuelDisplay
    // fuel bar fill fraction — follows the self-test sweep, else the live level
    readonly property real fuelBarFrac: selfTest ? (sweepFrac * (1 - settle) + (fuelLevel / 100) * settle) : fuelLevel / 100

    // Rev-lag debug overlay: set true to compare raw vs smoothed rpm when
    // tuning a dash's needle response. Off for normal use.
    property bool showRawRpm: false
    // Raw-sensor overlay: set true to see the RAW values the host sends, to
    // verify unit/scale assumptions (e.g. is oilpressuredata really PSI?). Off
    // for normal use.
    property bool showRawSensors: false

    // ---- repaint ----------------------------------------------------------
    //  The dash is declarative scene-graph nodes apart from the static `bg`
    //  canvas (chrome painted once). The tach ticks/glow, readouts, telltales
    //  and buttons update themselves through bindings — there is no per-frame
    //  canvas to pump. `bg` repaints only when a chrome-changing setting (rpm
    //  scale, side-gauge units) changes; those handlers live just below.

    // ---- derived ----------------------------------------------------------
    property bool overrev: rpmShown >= rpmredline    // crossed the shift value
    // engine off / key-on-engine-off: rpm sits at 0 (a running engine idles well
    // above 0). Used to show a centred placeholder instead of a lone right-aligned
    // "0", which looks lost in the fixed-width box until the car starts.
    property bool engineOff: !selfTest && Math.round(rpmShown) < 1
    // RPM / Speed placement: false (default) keeps RPM big on top with speed
    // below; true swaps them. Each value keeps its own formatting (fixed-width
    // rpm, speed unit, engine-off dashes); only the slot it occupies changes.
    property bool placementSwap: false
    // Hide the 1k tach scale numbers when true (default false = shown).
    property bool hideTachNums: false
    // Hide the three shift lights below the tach when true (default false).
    property bool hideShiftLights: false
    property bool showModeButtons: false   // RACE/SPORT buttons hidden unless enabled (some models lack them)
    property int  vShift: 0                 // V-SHIFT: move whole dash up/down (tall-driver aid), +/-40px
    property int  speedShown: (speedunits === 0) ? speed : Math.round(speed / 1.609)
    property string gearLabel: {
        if ((root.inputs & 0x4000000) !== 0) return "R";   // reverse bit forces "R"
        switch (gearpos) {
            case 0: return "N"; case 9: return "P"; case 10: return "R";
            default: return (gearpos >= 1 && gearpos <= 8) ? String(gearpos) : "N";
        }
    }

    // ---- side-gauge helpers (one set per 'kind'; called from the declarative
    //  delegates below). Each reads live root.* values, so the QML bindings that
    //  call them update automatically when a reading or setting changes — no
    //  canvas repaint involved.
    function gaugeShown(k) {
        return k === "oiltemp" ? showOilTemp : k === "oilpress" ? showOilPress
             : k === "afr"     ? showAfr     : showCoolant;
    }
    function gaugeLabel(k) {
        return k === "oiltemp" ? "OIL TEMP" : k === "oilpress" ? "OIL PRESS"
             : k === "afr"     ? "AFR"      : "COOLANT";
    }
    function gaugeWarn(k) {
        if (k === "oiltemp")  return oiltemp  >= oilTempHigh;
        if (k === "oilpress") return (!engineOff && oilPressShown <= oilPressLow) || oilPressShown >= oilPressHigh;
        if (k === "afr")      { var l = afr / 14.7; return l < afrLow || l > afrHigh; }
        return watertemp >= coolantHigh;   // coolant
    }
    function gaugeFrac(k) {
        var f;
        if (k === "oiltemp")       f = (oiltemp  - oilTempLow)  / Math.max(1, oilTempHigh  - oilTempLow);
        else if (k === "oilpress") f = (oilPressShown - oilPressLow) / Math.max(1, oilPressHigh - oilPressLow);
        else if (k === "afr")    { var l = afr / 14.7; f = (l - afrLow) / Math.max(0.001, afrHigh - afrLow); }
        else                       f = (watertemp - coolantLow) / Math.max(1, coolantHigh - coolantLow);
        return Math.max(0, Math.min(1, f));
    }
    function gaugeVal(k) {
        if (k === "oiltemp")  return String(Math.round(oilTempUnits === 0 ? oiltemp : oiltemp * 9/5 + 32));
        if (k === "oilpress") return oilPressUnits === 0 ? String(Math.round(oilPressShown)) : (oilPressShown / 14.5038).toFixed(1);
        if (k === "afr")      return afrSource === 0 ? afrShown.toFixed(1) : afrShown.toFixed(2);
        return String(Math.round(tempunits === 0 ? watertemp : watertemp * 9/5 + 32));   // coolant
    }
    function gaugeUnit(k) {
        if (k === "oiltemp")  return oilTempUnits  === 0 ? "\u00B0C" : "\u00B0F";
        if (k === "oilpress") return oilPressUnits === 0 ? "PSI" : "BAR";
        if (k === "afr")      return afrSource === 1 ? "\u03BB" : "";
        return tempunits === 0 ? "\u00B0C" : "\u00B0F";   // coolant
    }

    // odo/trip distance conversion (km native -> selected unit)
    readonly property real distFactor: (distunits === 0) ? 1.0 : 0.621371
    readonly property string distUnit: (distunits === 0) ? " km" : " mi"


    // =======================================================================
    //  THE GAUGE — a STATIC canvas layer (painted once; repainted only when a
    //  setting that changes the chrome does) under a declarative, GPU-composited
    //  layer for everything that moves.
    // =======================================================================
    onRevRedStartChanged:   bg.requestPaint()
    onRpmmaxChanged:        bg.requestPaint()
    onHideTachNumsChanged:  bg.requestPaint()
    onAccentChanged:        bg.requestPaint()
    onBgKeyChanged:         bg.requestPaint()

    property bool blinkOn: true          // shared 420 ms blink phase (warnings / shift flash)

    // =======================================================================
    //  HETHEL RACE visuals — shared geometry, colour and animation state
    // =======================================================================
    // ---- rev-bar arch geometry. The bar is a slice of a very large circle whose
    //      centre sits far below the screen, so the segments fan along a shallow
    //      arch across the top (Emira Track-mode style). Angles are degrees from
    //      vertical: -arcHalf (0 rpm, left) .. +arcHalf (RPM LIMIT, right).
    readonly property real arcCx:   400
    readonly property real arcCy:   1458
    readonly property real arcRi:   1356      // inner radius (segment roots)
    readonly property real arcHalf: 14.9
    readonly property int  segCount: Math.floor(rpmmax / 100) + 1
    readonly property real segPitch: (2 * arcHalf * Math.PI / 180) * 1378 / Math.max(1, segCount - 1)
    readonly property real segW:     Math.max(2, segPitch - 2.6)
    function arcTheta(v) { return -arcHalf + Math.max(0, Math.min(1, v / Math.max(1, rpmmax))) * 2 * arcHalf; }
    function arcRo(v)    { return arcRi + 36 + 14 * Math.max(0, Math.min(1, v / Math.max(1, rpmmax))); }   // wedge: taller toward the limit
    // index of the last lit segment. An int, so the ~90 segment bindings only
    // re-evaluate when the revs actually cross a segment — not on every frame.
    readonly property int litIndex: Math.floor((rpmShown + 30) / 100)

    // ---- Lotus palette: the accent (RED/GREEN/BLUE settings) is the yellow; the
    //      green is fixed. The rev bar runs green -> yellow -> red.
    readonly property string lotusGreen: sunset ? "#2ee6d6" : "#1fd071"     // bar-fill colour (teal in SUNSET)
    function segColor(v) {
        var acc = Qt.rgba(aR / 255, aG / 255, aB / 255, 1);
        // zone colours: Lotus green / yellow / red, or teal / orange / hot pink in SUNSET
        var zg = sunset ? [46, 230, 214] : [31, 208, 113];
        var zy = sunset ? [255, 176, 58] : [255, 224, 0];
        var zr = sunset ? [255, 45, 111] : [255, 41, 41];
        if (barColours === 1) {                                    // ZONES
            if (v >= redFrom)    return Qt.rgba(zr[0] / 255, zr[1] / 255, zr[2] / 255, 1);
            if (v >= yellowFrom) return Qt.rgba(zy[0] / 255, zy[1] / 255, zy[2] / 255, 1);
            if (v >= greenFrom)  return Qt.rgba(zg[0] / 255, zg[1] / 255, zg[2] / 255, 1);
            return acc;
        }
        if (v >= rpmredline) return Qt.rgba(zr[0] / 255, zr[1] / 255, zr[2] / 255, 1);
        if (barColours === 0) return acc;                          // ACCENT
        var t = (v / Math.max(1, rpmredline) - 0.42) / 0.30;      // BLEND: green->accent over 42%..72% of SHIFT RPM
        t = Math.max(0, Math.min(1, t));
        return Qt.rgba((zg[0] + (aR - zg[0]) * t) / 255,
                       (zg[1] + (aG - zg[1]) * t) / 255,
                       (zg[2] + (aB - zg[2]) * t) / 255, 1);
    }

    // ---- power-on intro: side gauges slide in from the edges and the centre
    //      fades up while the rev bar does its self-test sweep.
    property real intro: 0
    NumberAnimation { id: introAnim; target: root; property: "intro"; from: 0; to: 1; duration: 900; easing.type: Easing.OutCubic }

    // ---- gear-change pop: the gear digit punches up and settles, with an accent
    //      flash behind it. Event-driven (runs only on a gear change).
    property real gearScale: 1
    property real gearFlash: 0
    ParallelAnimation {
        id: gearPop
        SequentialAnimation {
            NumberAnimation { target: root; property: "gearScale"; to: 1.30; duration: 60 }
            NumberAnimation { target: root; property: "gearScale"; to: 1.00; duration: 280; easing.type: Easing.OutBack }
        }
        NumberAnimation { target: root; property: "gearFlash"; from: 0.8; to: 0; duration: 450; easing.type: Easing.OutQuad }
    }
    // gear roll: the old digit slides out and the new one slides in — up on an
    // upshift, down on a downshift. FX: GEAR ROLL off falls back to the pop.
    property string gearLast: "N"       // digit shown before the latest change
    property string gearOld:  "N"       // digit sliding out
    property real   gearRoll: 1         // 0 = old digit showing ... 1 = new digit settled
    property int    gearDir:  1         // +1 upshift, -1 downshift
    function gearOrd(l) { return l === "R" ? -1 : ((l === "N" || l === "P") ? 0 : parseInt(l)); }
    NumberAnimation { id: gearRollAnim;  target: root; property: "gearRoll";  from: 0;   to: 1; duration: 230; easing.type: Easing.OutCubic }
    NumberAnimation { id: gearFlashAnim; target: root; property: "gearFlash"; from: 0.8; to: 0; duration: 450; easing.type: Easing.OutQuad }
    onGearLabelChanged: {
        gearOld = gearLast; gearLast = gearLabel;
        if (selfTest) return;
        gearDir = gearOrd(gearLabel) >= gearOrd(gearOld) ? 1 : -1;
        if (fxRoll) { gearRollAnim.restart(); gearFlashAnim.restart(); }
        else gearPop.restart();
    }

    // ---- limiter stutter: at RPM LIMIT the last lit segments flicker fast
    readonly property bool limiting: fxLimiter && !selfTest && rpmShown >= rpmmax - 150
    property bool limPhase: true
    Timer { interval: 55; repeat: true; running: root.limiting; onTriggered: root.limPhase = !root.limPhase }

    // ---- launch mode: stationary with the revs up -> target band on the bar
    readonly property bool launchArmed: fxLaunch && !selfTest && speed < 3 && rpmShown >= 2000 && gearLabel !== "R"
    readonly property bool launchReady: launchArmed && Math.abs(rpmShown - launchRpm) <= 300
    property real launchFlash: 0
    NumberAnimation { id: launchGo; target: root; property: "launchFlash"; from: 1; to: 0; duration: 900; easing.type: Easing.OutQuad }
    onLaunchArmedChanged: if (!launchArmed && fxLaunch && speed >= 3) launchGo.restart()

    // ---- accel / brake bar: longitudinal g from the change in road speed over
    //      the last 0.5 s (10 Hz sampling; 1 g = 35.3 km/h per second)
    property var  spdBuf: []
    property real accelG: 0
    Timer {
        interval: 100; repeat: true; running: root.fxAccel || root.rightWing === 5
        onTriggered: {
            var b = root.spdBuf; b.push(root.speed); if (b.length > 6) b.shift();
            var g = (b.length > 1) ? (b[b.length - 1] - b[0]) / ((b.length - 1) * 0.1) / 35.3 : 0;
            g = Math.max(-1.2, Math.min(1.2, g));
            if (Math.abs(g - root.accelG) >= 0.02 || (g === 0 && root.accelG !== 0)) root.accelG = g;
        }
    }

    // ---- new-best flash: when the right wing shows MAX SPEED / MAX RPM and the
    //      session max is beaten, the value counts up and flashes green once the
    //      run-up ends. A new best 0-60 time flashes the same way.
    readonly property real maxTarget: rightWing === 2 ? (speedunits === 0 ? peakSpeed : peakSpeed / 1.609)
                                    : rightWing === 3 ? peakRpm : 0
    property real maxPrev: 0
    property real bestFlash: 0
    NumberAnimation { id: bestAnim; target: root; property: "bestFlash"; from: 1; to: 0; duration: 1100; easing.type: Easing.OutQuad }
    Timer { id: bestSettle; interval: 500; repeat: false; onTriggered: if (root.fxBest && !root.selfTest) bestAnim.restart() }
    onMaxTargetChanged: { if (maxTarget > maxPrev + 1) bestSettle.restart(); maxPrev = maxTarget; }

    // ---- RACE mode takeover (RACE input, 0x800000): the side gauges shrink back
    //      and the gear + rev bar grow.
    readonly property bool raceOn: fxRace && tRace
    property real raceAmt: raceOn ? 1 : 0
    Behavior on raceAmt { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }

    // ---- critical warning takeover: low oil pressure / coolant overtemp slide a
    //      red banner across the centre (in, hold, out). The side box keeps pulsing.
    readonly property bool critOil:  !selfTest && showOilPress && !engineOff && oilPressShown <= oilPressLow
    readonly property bool critCool: !selfTest && showCoolant && watertemp >= coolantHigh
    readonly property bool critAny:  critOil || critCool
    property real bannerX: -800
    property string bannerText: ""
    SequentialAnimation {
        id: bannerAnim
        NumberAnimation { target: root; property: "bannerX"; from: -800; to: 0;   duration: 320; easing.type: Easing.OutCubic }
        PauseAnimation  { duration: 2600 }
        NumberAnimation { target: root; property: "bannerX"; from: 0;    to: 800; duration: 320; easing.type: Easing.InCubic }
    }
    // 700 ms confirm so the oil-pressure build-up at engine start does not fire it
    Timer { id: critConfirm; interval: 700; repeat: false
            onTriggered: if (root.critAny && root.fxBanner) {
                root.bannerText = root.critOil ? "LOW OIL PRESSURE" : "COOLANT OVERTEMP";
                bannerAnim.restart(); } }
    onCritOilChanged:  if (critOil)  critConfirm.restart()
    onCritCoolChanged: if (critCool) critConfirm.restart()

    // ---- cold-engine rev ceiling: until the oil reaches OIL TEMP LOW the bar
    //      shows a blue band above a reduced ceiling, which rises from 55 % of
    //      SHIFT RPM (50 deg C below OIL TEMP LOW) to 100 % as the oil warms.
    readonly property bool coldActive: fxCold && !selfTest && showOilTemp && oiltemp < oilTempLow
    readonly property real coldCeil: rpmredline * (0.55 + 0.45 * Math.max(0, Math.min(1, (oiltemp - (oilTempLow - 50)) / 50)))
    readonly property int  coldIndex: coldActive ? Math.ceil(coldCeil / 100) : 99999

    // ---- shutdown sweep: when a running engine stops, everything slides / fades
    //      out (mirror of the power-on intro), then returns for key-on readings.
    property bool wasRunning: false
    SequentialAnimation {
        id: shutdownAnim
        NumberAnimation { target: root; property: "intro"; to: 0; duration: 520; easing.type: Easing.InCubic }
        PauseAnimation  { duration: 500 }
        NumberAnimation { target: root; property: "intro"; to: 1; duration: 700; easing.type: Easing.OutCubic }
    }
    onEngineOffChanged: {
        if (!engineOff) { wasRunning = true; return; }
        if (wasRunning && fxShutdown && !selfTest) shutdownAnim.restart();
        wasRunning = false;
    }

    // ---- rev tell-tale: a marker that rides the peak of each rev, holds for a
    //      moment, then falls back (race-tach tell-tale). Idle when revs are steady.
    property real rpmTell: 0
    onRpmShownChanged: {
        if (selfTest) return;
        if (rpmShown >= rpmTell) { tellFall.stop(); rpmTell = rpmShown; tellHold.restart(); }
        else if (!tellFall.running && !tellHold.running) tellHold.restart();
    }
    onRpmTellChanged: if (rpmTell < rpmShown) { tellFall.stop(); rpmTell = rpmShown; }
    Timer { id: tellHold; interval: 1400; repeat: false; onTriggered: tellFall.start() }
    NumberAnimation { id: tellFall; target: root; property: "rpmTell"; to: 0; duration: 1800; easing.type: Easing.InQuad }

    // ---- live dash view (wrapped so the settings page can show a preview) --
    Item {
        id: dashView
        anchors.fill: parent
        Item {
            id: dashShift
            anchors.fill: parent
            transform: Translate { y: root.vShift }   // V-SHIFT lives here so the live preview shows it too

    // ---- STATIC layer ------------------------------------------------------
    Canvas {
        id: bg
        anchors.fill: parent
        antialiasing: true
        renderStrategy: Canvas.Cooperative

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            drawBackdrop(ctx);       // green-black gradient, centre glow, hex weave, bottom bar
            drawArcStatic(ctx);      // unlit rev-bar segments + hairline
            drawArcNumbers(ctx);     // 1k scale labels under the bar
            drawCentreStatic(ctx);   // gear shield + wings
        }

        function drawBackdrop(ctx) {
            var g = ctx.createLinearGradient(0, 0, 0, height);
            g.addColorStop(0.0, root.bgS(0.033, 1)); g.addColorStop(0.55, root.bgS(0.117, 4)); g.addColorStop(1.0, root.bgS(0.042, 1));
            ctx.fillStyle = g; ctx.fillRect(0, 0, width, height);
            if (root.mapBg) { drawMap(ctx); } else if (root.sunset) { drawSunset(ctx); } else {
            // deep-green glow behind the gear
            var rg = ctx.createRadialGradient(400, 205, 10, 400, 205, 330);
            rg.addColorStop(0.0, root.bgA(1, 0, 0.42)); rg.addColorStop(1.0, root.bgA(1, 0, 0));
            ctx.fillStyle = rg; ctx.fillRect(0, 60, width, 310);
            // faint hexagon weave, fading out from the centre
            var R = 15, dx = R * Math.sqrt(3), dy = R * 1.5;
            ctx.lineWidth = 1;
            for (var row = 0; row * dy < 250; row++) {
                var y = 130 + row * dy;
                for (var col = 0; col * dx < 460; col++) {
                    var x = 170 + col * dx + ((row % 2) ? dx / 2 : 0);
                    var dd = Math.sqrt((x - 400) * (x - 400) + (y - 215) * (y - 215) * 1.6);
                    var al = 0.20 * (1 - dd / 240);
                    if (al < 0.012) continue;
                    ctx.strokeStyle = root.bgA(1.1, 60, al);
                    ctx.beginPath();
                    for (var k = 0; k < 6; k++) {
                        var a = (60 * k + 30) * Math.PI / 180;
                        if (k === 0) ctx.moveTo(x + R * Math.cos(a), y + R * Math.sin(a));
                        else         ctx.lineTo(x + R * Math.cos(a), y + R * Math.sin(a));
                    }
                    ctx.closePath(); ctx.stroke();
                }
            }
            }
            // bottom bar
            ctx.fillStyle = root.bgS(0.142, 6); ctx.fillRect(0, 366, width, 44);
            ctx.fillStyle = root.bgS(0.508, 29); ctx.fillRect(0, 366, width, 2);
            ctx.fillStyle = root.accentInk; ctx.fillRect(330, 366, 140, 2);
            ctx.fillStyle = root.bgS(0.325, 14); ctx.fillRect(0, 408, width, 2);
        }

        // SUNSET theme backdrop: dusk sky, a striped setting sun on the horizon and
        // palm silhouettes in the wings (all static, painted once)
        function drawSunset(ctx) {
            var g = ctx.createLinearGradient(0, 0, 0, 366);
            g.addColorStop(0.0, "#0c0422"); g.addColorStop(0.45, "#2a0f5c"); g.addColorStop(0.82, "#6a1f7c"); g.addColorStop(1.0, "#b83b78");
            ctx.fillStyle = g; ctx.fillRect(0, 0, width, 366);
            ctx.save();
            ctx.beginPath(); ctx.rect(0, 0, width, 366); ctx.clip();
            var sg = ctx.createLinearGradient(0, 240, 0, 366);
            sg.addColorStop(0.0, "rgba(255,214,90,0.42)"); sg.addColorStop(1.0, "rgba(255,70,150,0.42)");
            ctx.fillStyle = sg;
            ctx.beginPath(); ctx.arc(400, 366, 126, Math.PI, 2 * Math.PI); ctx.fill();
            ctx.fillStyle = "rgba(70,20,110,0.85)";                 // horizon stripes across the sun
            for (var i = 0; i < 6; i++) ctx.fillRect(264, 286 + i * 14, 272, 2 + i * 1.6);
            ctx.restore();
            palm(ctx, 236, 366, 112, -16); palm(ctx, 292, 366, 76, 10);
            palm(ctx, 564, 366, 112, 16);  palm(ctx, 508, 366, 76, -10);
        }
        // CITY MAP theme backdrop: a night-mode street map — angled city blocks with
        // blue buildings, a sand beach and the sea (an invented layout, painted once)
        function drawMap(ctx) {
            ctx.fillStyle = "#2a3350"; ctx.fillRect(0, 0, width, 366);            // roads show through the gaps
            ctx.save();
            ctx.beginPath(); ctx.rect(0, 0, width, 366); ctx.clip();
            ctx.translate(400, 190); ctx.rotate(-0.36);
            for (var i = -5; i <= 5; i++) {
                for (var j = -5; j <= 5; j++) {
                    var bx = i * 122 - 52, by = j * 88 - 36;
                    ctx.fillStyle = "#19213a"; ctx.fillRect(bx, by, 106, 74);     // city block
                    var h = ((i * 7 + j * 13) % 5 + 5) % 5;                       // which buildings this block gets
                    if (h < 3) building(ctx, bx + 10, by + 10, 38 + h * 9, 22);
                    if (h === 1 || h === 4) building(ctx, bx + 58, by + 36, 34, 26);
                    if (h === 2) building(ctx, bx + 14, by + 44, 22, 18);
                }
            }
            // beach + sea on the right (a wavy coast, diagonal on screen)
            ctx.fillStyle = "#6f6440";
            ctx.beginPath(); ctx.moveTo(250, -500);
            ctx.quadraticCurveTo(210, -200, 262, -40); ctx.quadraticCurveTo(300, 90, 236, 250); ctx.quadraticCurveTo(210, 380, 250, 520);
            ctx.lineTo(900, 520); ctx.lineTo(900, -500); ctx.closePath(); ctx.fill();
            var wg = ctx.createLinearGradient(310, 0, 620, 0);
            wg.addColorStop(0.0, "#1e62b8"); wg.addColorStop(1.0, "#0f2f6e");
            ctx.fillStyle = wg;
            ctx.beginPath(); ctx.moveTo(322, -500);
            ctx.quadraticCurveTo(286, -200, 334, -40); ctx.quadraticCurveTo(372, 90, 310, 250); ctx.quadraticCurveTo(284, 380, 322, 520);
            ctx.lineTo(900, 520); ctx.lineTo(900, -500); ctx.closePath(); ctx.fill();
            ctx.restore();
            // calm the centre so the readouts stay legible
            var vg = ctx.createRadialGradient(400, 215, 30, 400, 215, 360);
            vg.addColorStop(0.0, "rgba(8,12,34,0.80)"); vg.addColorStop(0.55, "rgba(8,12,34,0.55)"); vg.addColorStop(1.0, "rgba(8,12,34,0.25)");
            ctx.fillStyle = vg; ctx.fillRect(0, 0, width, 366);
        }
        function building(ctx, x, y, w, h) {       // extruded block: darker side, lighter roof offset up-left
            ctx.fillStyle = "#1f3f8c"; ctx.fillRect(x, y, w, h);
            ctx.fillStyle = "#3566cc"; ctx.fillRect(x - 3, y - 5, w, h);
        }
        function palm(ctx, x, base, h, lean) {
            var tx = x + lean, ty = base - h, col = "#12052a";
            ctx.strokeStyle = col; ctx.fillStyle = col; ctx.lineWidth = Math.max(3, h * 0.045);
            ctx.beginPath(); ctx.moveTo(x, base); ctx.quadraticCurveTo(x + lean * 0.15, base - h * 0.6, tx, ty); ctx.stroke();
            var angs = [-172, -140, -108, -72, -40, -8, 22, 158], len = h * 0.52;
            for (var i = 0; i < angs.length; i++) {
                var a = angs[i] * Math.PI / 180, cx = Math.cos(a), sy = Math.sin(a);
                var ex = tx + len * cx, ey = ty + len * sy + len * 0.30;      // tip droops
                ctx.beginPath(); ctx.moveTo(tx, ty);
                ctx.quadraticCurveTo(tx + len * 0.55 * cx, ty + len * 0.55 * sy - len * 0.22, ex, ey);
                ctx.quadraticCurveTo(tx + len * 0.50 * cx, ty + len * 0.50 * sy + len * 0.04, tx, ty);
                ctx.fill();
            }
        }

        // unlit baseline segments, one per 100 rpm (the lit ones are scene-graph
        // Rectangles drawn exactly over these)
        function drawArcStatic(ctx) {
            for (var v = 0; v <= root.rpmmax; v += 100) {
                var th = root.arcTheta(v) * Math.PI / 180;
                var major = (v % 1000 === 0), redZone = (v >= root.revRedStart);
                var ri = major ? root.arcRi - 7 : root.arcRi, ro = root.arcRo(v);
                var rm = (ri + ro) / 2;
                ctx.save();
                ctx.translate(root.arcCx + rm * Math.sin(th), root.arcCy - rm * Math.cos(th));
                ctx.rotate(th);
                ctx.fillStyle = redZone ? (root.light ? "#f0c0c0" : "#571a1a") : (major ? root.bgS(0.525, 44) : root.bgS(0.317, 20));
                ctx.fillRect(-root.segW / 2, -(ro - ri) / 2, root.segW, ro - ri);
                ctx.restore();
            }
            // hairline under the bar
            var a0 = (-90 - root.arcHalf) * Math.PI / 180, a1 = (-90 + root.arcHalf) * Math.PI / 180;
            ctx.strokeStyle = root.bgS(0.508, 29); ctx.lineWidth = 2;
            ctx.beginPath(); ctx.arc(root.arcCx, root.arcCy, root.arcRi - 12, a0, a1); ctx.stroke();
        }

        function drawArcNumbers(ctx) {
            if (root.hideTachNums) return;
            ctx.font = "bold 19px " + root.ff; ctx.textAlign = "center"; ctx.textBaseline = "middle";
            var rLbl = root.arcRi - 24;
            for (var n = 0; n * 1000 <= root.rpmmax; n++) {
                var th = root.arcTheta(n * 1000) * Math.PI / 180;
                ctx.fillStyle = (n * 1000 >= root.revRedStart) ? root.redSoft : root.fg2;
                ctx.fillText(String(n), root.arcCx + rLbl * Math.sin(th), root.arcCy - rLbl * Math.cos(th));
            }
        }

        function drawCentreStatic(ctx) {
            // chamfered gear shield (centre 400,200)
            shield(ctx, 400, 200, 66, 62, 20);
            var g = ctx.createLinearGradient(0, 138, 0, 262);
            g.addColorStop(0, root.bgS(0.25, 12)); g.addColorStop(1, root.bgS(0.083, 3));
            ctx.fillStyle = g; ctx.fill();
            shield(ctx, 400, 200, 66, 62, 20); ctx.strokeStyle = root.accentInk; ctx.lineWidth = 2.5; ctx.stroke();
            shield(ctx, 400, 200, 59, 55, 17); ctx.strokeStyle = root.bgS(0.508, 29); ctx.lineWidth = 1.5; ctx.stroke();
            // wings: hairline + three slashes each side, pointing at the shield
            ctx.lineWidth = 2; ctx.strokeStyle = root.bgS(0.508, 29);
            ctx.beginPath(); ctx.moveTo(200, 236); ctx.lineTo(296, 236); ctx.stroke();
            ctx.beginPath(); ctx.moveTo(504, 236); ctx.lineTo(600, 236); ctx.stroke();
            ctx.fillStyle = root.accentInk;
            for (var i = 0; i < 3; i++) {
                ctx.globalAlpha = 1.0 - i * 0.3;
                slash(ctx, 322 - i * 9, 229, 1); slash(ctx, 478 + i * 9, 229, -1);
            }
            ctx.globalAlpha = 1.0;
        }
        function shield(ctx, cx, cy, hw, hh, c) {
            ctx.beginPath();
            ctx.moveTo(cx - hw + c, cy - hh); ctx.lineTo(cx + hw - c, cy - hh);
            ctx.lineTo(cx + hw, cy - hh + c); ctx.lineTo(cx + hw, cy + hh - c);
            ctx.lineTo(cx + hw - c, cy + hh); ctx.lineTo(cx - hw + c, cy + hh);
            ctx.lineTo(cx - hw, cy + hh - c); ctx.lineTo(cx - hw, cy - hh + c);
            ctx.closePath();
        }
        function slash(ctx, x, y, dir) {   // small slanted bar (14 px tall, 5 px wide)
            ctx.beginPath();
            ctx.moveTo(x, y); ctx.lineTo(x + 5, y); ctx.lineTo(x + 5 - dir * 6, y + 14); ctx.lineTo(x - dir * 6, y + 14);
            ctx.closePath(); ctx.fill();
        }
    }

    // ---- REV BAR (declarative, GPU-composited) -----------------------------
    //  One Rectangle per 100 rpm, rotated onto the arch, lit by `litIndex`.
    //  Lighting is instant; un-lighting fades, which leaves a short comet tail
    //  when the revs drop. A wide low-opacity sibling per segment is the glow.
    //  Past SHIFT RPM the whole lit bar turns red and flashes.
    Item {
        id: tachLit
        anchors.fill: parent

        Repeater {
            model: root.segCount
            delegate: Item {
                id: seg
                readonly property int    v:      index * 100
                readonly property bool   major:  (v % 1000) === 0
                readonly property bool   lit:    index <= root.litIndex
                readonly property real   th:     root.arcTheta(v)
                readonly property real   thR:    th * Math.PI / 180
                readonly property real   ri:     major ? root.arcRi - 7 : root.arcRi
                readonly property real   ro:     root.arcRo(v) + 7 * root.raceAmt      // RACE mode: lit bar grows
                readonly property real   rmid:   (ri + ro) / 2
                readonly property real   px:     root.arcCx + rmid * Math.sin(thR)
                readonly property real   py:     root.arcCy - rmid * Math.cos(thR)
                readonly property color  zoneCol: root.segColor(v)
                readonly property color  litCol:  root.overrev ? "#ff2a2a" : zoneCol
                readonly property bool   hot:    root.fxBloom && v >= root.revRedStart             // redline bloom
                readonly property bool   cold:   index >= root.coldIndex && v < root.revRedStart   // cold-oil band
                readonly property bool   lim:    root.limiting && index > root.litIndex - 6        // limiter stutter

                Rectangle {   // soft glow (wider + stronger in the red zone)
                    width: root.segW + (seg.hot ? 18 : 9); height: seg.ro - seg.ri + (seg.hot ? 22 : 12); radius: 5
                    antialiasing: true
                    color: seg.litCol
                    opacity: seg.lit ? (seg.hot ? 0.30 : 0.17) : 0
                    x: seg.px - width / 2; y: seg.py - height / 2
                    rotation: seg.th
                }
                Rectangle {   // lit segment (overdraws the dim baseline on bg)
                    width: root.segW; height: seg.ro - seg.ri
                    antialiasing: true
                    color: (seg.lit || !seg.cold) ? seg.litCol : "#3a9dff"
                    opacity: seg.lit ? ((seg.lim && !root.limPhase) ? 0.10
                                        : ((root.overrev && !root.blinkOn) ? 0.45 : 1))
                                     : (seg.cold ? 0.55 : 0)
                    Behavior on opacity { NumberAnimation { duration: seg.lit ? 0 : 170 } }   // fade OUT only -> comet tail
                    x: seg.px - width / 2; y: seg.py - height / 2
                    rotation: seg.th
                }
            }
        }

        // white-hot leading edge riding the live rev position
        Item {
            id: revHead
            visible: root.rpmShown > 60
            readonly property real th:  root.arcTheta(root.rpmShown)
            readonly property real thR: th * Math.PI / 180
            readonly property real ro:  root.arcRo(root.rpmShown) + 7 * root.raceAmt
            readonly property bool hot: root.fxBloom && root.rpmShown >= root.revRedStart
            readonly property real rm:  (root.arcRi + ro) / 2
            Rectangle {
                width: root.segW + (revHead.hot ? 34 : 14); height: revHead.ro - root.arcRi + (revHead.hot ? 34 : 18); radius: 9
                antialiasing: true; color: revHead.hot ? "#ff5a3a" : root.fg; opacity: revHead.hot ? 0.30 : 0.16
                Behavior on width { NumberAnimation { duration: 180 } }
                x: root.arcCx + revHead.rm * Math.sin(revHead.thR) - width / 2
                y: root.arcCy - revHead.rm * Math.cos(revHead.thR) - height / 2
                rotation: revHead.th
            }
            Rectangle {
                width: Math.max(3, root.segW * 0.7); height: revHead.ro - root.arcRi + 6
                antialiasing: true; color: root.fg
                x: root.arcCx + revHead.rm * Math.sin(revHead.thR) - width / 2
                y: root.arcCy - revHead.rm * Math.cos(revHead.thR) - height / 2
                rotation: revHead.th
            }
        }

        // tell-tale marker (peak of the last rev; holds, then falls back)
        Rectangle {
            id: tellMark
            readonly property real th:  root.arcTheta(root.rpmTell)
            readonly property real thR: th * Math.PI / 180
            readonly property real ro:  root.arcRo(root.rpmTell) + 5
            readonly property real rm:  (root.arcRi + ro) / 2
            width: 3; height: ro - root.arcRi + 4
            antialiasing: true
            color: root.rpmTell >= root.revRedStart ? "#ff5555" : root.accentInk
            opacity: (!root.selfTest && root.rpmTell > root.rpmShown + 150) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
            x: root.arcCx + rm * Math.sin(thR) - width / 2
            y: root.arcCy - rm * Math.cos(thR) - height / 2
            rotation: th
        }
    }

    // ---- markers on the rev bar: launch target band --------------------------
    Item {
        id: barMarks
        anchors.fill: parent
        Repeater {    // launch band edges (LAUNCH RPM +/- 300)
            model: [ -300, 300 ]
            Rectangle {
                readonly property real v:   root.launchRpm + modelData
                readonly property real th:  root.arcTheta(v)
                readonly property real thR: th * Math.PI / 180
                readonly property real ro:  root.arcRo(v) + 12
                readonly property real rm:  (root.arcRi - 10 + ro) / 2
                width: 4; height: ro - root.arcRi + 10; radius: 2
                antialiasing: true
                color: root.launchReady ? root.lotusGreen : root.fg
                opacity: root.launchArmed ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }
                visible: opacity > 0.01
                x: root.arcCx + rm * Math.sin(thR) - width / 2
                y: root.arcCy - rm * Math.cos(thR) - height / 2
                rotation: th
            }
        }
    }

    // ---- DYNAMIC readout layer (declarative) -------------------------------
    //  Every readout is a scene-graph Text/Rectangle node bound to its value, so
    //  only the node that changed re-renders (on the GPU).
    Item {
        id: readouts
        anchors.fill: parent

        // ===== shift lights: top centre, above the crown of the rev bar. Each
        // lights by its inputsdata bit OR by rpm (90 / 95 / 100 % of SHIFT RPM);
        // past the shift point everything lit flashes.
        Row {
            visible: !root.hideShiftLights && !root.fxSeq && !root.sunset
            anchors.horizontalCenter: parent.horizontalCenter
            y: 14; spacing: 18
            Repeater {
                model: [ { bit: 0x80000,  rpmFrac: 0.90 },
                         { bit: 0x100000, rpmFrac: 0.95 },
                         { bit: 0x200000, rpmFrac: 1.00 } ]   // shift 1 / 2 / 3
                Image {
                    source: "assets/shiftlight.png"
                    height: 24
                    width: implicitHeight > 0 ? 24 * implicitWidth / implicitHeight : 34
                    fillMode: Image.PreserveAspectFit
                    smooth: true; antialiasing: true
                    opacity: {
                        var lit = ((root.inputs & modelData.bit) !== 0)
                                  || (root.rpmShown >= root.rpmredline * modelData.rpmFrac);
                        if (!lit) return 0.0;
                        return root.overrev ? (root.blinkOn ? 1.0 : 0.0) : 1.0;
                    }
                }
            }
        }

        // ===== sequential shift lights (FX: SEQ SHIFT LIGHTS): 12 LEDs that fill
        // from both ends toward the centre — green, yellow, red — from 82 % to
        // 100 % of SHIFT RPM, then the whole row flashes. The three inputsdata
        // shift bits light the outer / middle / inner pairs as well.
        Row {
            visible: !root.hideShiftLights && root.fxSeq && !root.sunset
            anchors.horizontalCenter: parent.horizontalCenter
            y: 20; spacing: 6
            Repeater {
                model: 12
                Rectangle {
                    readonly property int  pair: index < 6 ? index : 11 - index          // 0 = outer ... 5 = centre
                    readonly property int  bit:  pair < 2 ? 0x80000 : (pair < 4 ? 0x100000 : 0x200000)
                    readonly property bool lit:  root.rpmShown >= root.rpmredline * (0.82 + 0.036 * pair)
                                                 || (root.inputs & bit) !== 0
                    width: 22; height: 10; radius: 5
                    color: !lit ? root.bgS(0.208, 16)
                         : (root.overrev ? (root.blinkOn ? "#ff2a2a" : (root.light ? "#f0b4b4" : "#3a0d0d"))
                         : (pair < 2 ? root.lotusGreen : (pair < 4 ? "#ffe000" : "#ff2a2a")))
                    border.width: 1; border.color: lit ? root.fg : root.bgS(0.508, 29)
                }
            }
        }

        // ===== SUNSET theme shift lights: five stars that fill left to right from
        // 60 % to 100 % of SHIFT RPM (the shift bits light stars 3 / 4 / 5 too); at
        // the shift point all five flash red / blue.
        Row {
            visible: !root.hideShiftLights && root.sunset
            anchors.horizontalCenter: parent.horizontalCenter
            y: 4; spacing: 12
            Repeater {
                model: 5
                Text {
                    readonly property int  bit: index === 2 ? 0x80000 : (index === 3 ? 0x100000 : (index === 4 ? 0x200000 : 0))
                    readonly property bool lit: root.rpmShown >= root.rpmredline * (0.60 + 0.10 * index)
                                                || (bit !== 0 && (root.inputs & bit) !== 0)
                    text: lit ? "\u2605" : "\u2606"
                    color: !lit ? root.bgS(0.508, 29)
                         : (root.overrev ? (root.blinkOn ? "#ff2d55" : "#3d7bff") : "#fff4c2")
                    font.family: root.menuFont; font.pixelSize: 34
                    scale: lit ? 1.0 : 0.85
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                }
            }
        }

        // ===== gear, in the shield (centre 400,200) =====
        Rectangle {   // accent flash behind the digit on a gear change
            x: 343; y: 146; width: 114; height: 108; radius: 12
            color: root.accent; opacity: root.gearFlash * 0.55
            visible: opacity > 0.01
        }
        Rectangle {   // red "shift now" pulse inside the shield
            x: 343; y: 146; width: 114; height: 108; radius: 12
            color: "#ff2a2a"
            opacity: (root.overrev && root.blinkOn) ? 0.38 : 0
            Behavior on opacity { NumberAnimation { duration: 110 } }
            visible: opacity > 0.01
        }
        Rectangle {   // green "GO" flash when a launch moves off
            x: 343; y: 146; width: 114; height: 108; radius: 12
            color: root.lotusGreen; opacity: root.launchFlash * 0.7
            visible: opacity > 0.01
        }
        Item {
            x: 334; y: 138; width: 132; height: 124
            opacity: root.intro
            clip: root.gearRoll < 1          // only while a roll is in flight (the pop must not be clipped)
            Text {   // outgoing digit
                visible: root.gearRoll < 1
                text: root.gearOld
                color: root.fg; opacity: 1 - root.gearRoll
                font.family: root.dispFont; font.bold: root.dispBold; font.pixelSize: root.dispOn ? 134 : 104
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -1 - root.gearDir * root.gearRoll * 96
            }
            Text {   // current digit
                text: root.gearLabel
                color: root.overrev ? (root.light ? "#a01010" : "#ffe9e9") : (root.raceAmt > 0.5 ? root.accentInk : root.fg)
                opacity: 0.25 + 0.75 * root.gearRoll
                font.family: root.dispFont; font.bold: root.dispBold; font.pixelSize: root.dispOn ? 134 : 104
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -1 + root.gearDir * (1 - root.gearRoll) * 96
                scale: root.gearScale * (1 + 0.10 * root.raceAmt)
            }
        }

        // ===== primary readout: big, under the shield. Default = SPEED; the
        //       RPM/SPEED SWAP setting puts RPM here instead. =====
        Text {
            id: bigNum
            readonly property bool isRpm: root.placementSwap
            text: root.engineOff ? (isRpm ? "––––" : "–––")
                                 : (isRpm ? String(Math.round(root.rpmShown / 10) * 10) : String(root.speedShown))
            color: root.engineOff ? root.bgS(0.325, 63)
                 : ((isRpm && root.overrev) ? (root.blinkOn ? "#ff4040" : "#ff8a8a") : root.fg)
            font.family: root.dispFont; font.bold: root.dispBold; font.pixelSize: root.dispOn ? 74 : 58
            style: root.sunset ? Text.Outline : Text.Normal; styleColor: root.outlineCol     // keeps it readable over the sun
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.dispOn ? 252 : 260; opacity: root.intro
        }
        Text {
            readonly property bool launchMsg: root.launchFlash > 0.05 || root.launchArmed
            text: root.launchFlash > 0.05 ? "GO"
                : root.launchArmed ? (root.launchReady ? "READY" : (root.rpmShown < root.launchRpm ? "REV UP" : "TOO HIGH"))
                : (bigNum.isRpm ? "RPM" : (root.speedunits === 0 ? "KM/H" : "MPH"))
            color: launchMsg ? ((root.launchFlash > 0.05 || root.launchReady) ? root.greenInk : root.fg)
                             : (root.engineOff ? root.bgS(0.325, 63) : (root.sunset ? "#fff4c2" : root.accentInk))
            font.family: root.dispFont; font.bold: root.dispBold; font.pixelSize: (launchMsg ? 17 : 14) + (root.dispOn ? 2 : 0)
            style: root.sunset ? Text.Outline : Text.Normal; styleColor: root.outlineCol
            font.letterSpacing: 3
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.dispOn ? 327 : 325; opacity: root.intro
        }

        // ===== left wing: the secondary live readout (RPM by default) =====
        Text {
            text: bigNum.isRpm ? (root.speedunits === 0 ? "KM/H" : "MPH") : "RPM"
            color: root.engineOff ? root.bgS(0.325, 63) : ((!bigNum.isRpm && root.overrev) ? "#ff5555" : root.accentInk)
            font.family: root.dispFont; font.bold: root.dispBold; font.pixelSize: root.dispOn ? 16 : 12; font.letterSpacing: 2
            x: 248 - width / 2; y: 168; opacity: root.intro
        }
        Text {
            text: root.engineOff ? (bigNum.isRpm ? "–––" : "––––")
                                 : (bigNum.isRpm ? String(root.speedShown) : String(Math.round(root.rpmShown / 10) * 10))
            color: root.engineOff ? root.bgS(0.325, 63)
                 : ((!bigNum.isRpm && root.overrev) ? (root.blinkOn ? "#ff4040" : "#ff8a8a") : root.fg)
            font.family: root.dispFont; font.bold: root.dispBold; font.pixelSize: root.dispOn ? 44 : 34
            x: 248 - width / 2; y: root.dispOn ? 178 : 183; opacity: root.intro
        }
        // ===== right wing: selectable slot (RIGHT WING setting) =====
        Text {
            visible: root.rightWing < 6
            text: root.rightWing === 0 ? (root.speedunits === 0 ? "0-100 KM/H" : "0-60 MPH")
                : root.rightWing === 1 ? "FUEL"
                : root.rightWing === 2 ? (root.speedunits === 0 ? "MAX KM/H" : "MAX MPH")
                : root.rightWing === 3 ? "MAX RPM"
                : root.rightWing === 4 ? "SESSION" : "PEAK G"
            color: root.greenInk
            font.family: root.dispFont; font.bold: root.dispBold; font.pixelSize: root.dispOn ? 16 : 12; font.letterSpacing: 2
            x: 552 - width / 2; y: 168; opacity: root.intro
        }
        Text {
            id: maxVal
            visible: root.rightWing < 6
            property real shown: root.maxTarget
            Behavior on shown { enabled: root.fxBest; NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }   // count up
            text: root.rightWing === 0 ? (root.accState === 2 ? root.accNow.toFixed(1)
                                          : (root.accLast > 0 ? root.accLast.toFixed(2) : "\u2013\u2013.\u2013"))
                : root.rightWing === 1 ? (Math.round(root.fuelLevel) + "%")
                : root.rightWing === 2 ? String(Math.round(shown))
                : root.rightWing === 3 ? String(Math.round(shown / 10) * 10)
                : root.rightWing === 4 ? root.fmtSession(root.sessionSec)
                : ("+" + root.peakGAcc.toFixed(1) + " \u2212" + root.peakGBrk.toFixed(1))
            color: root.bestFlash > 0.03 ? root.greenInk
                 : (root.rightWing === 0 && root.accState === 2) ? root.accentInk
                 : (root.rightWing === 1 && !root.selfTest && root.fuelLevel < root.fuelLow) ? "#ff5050" : root.fg2
            scale: 1 + 0.16 * root.bestFlash
            font.family: root.dispFont; font.bold: root.dispBold; font.pixelSize: (root.rightWing === 5 ? 25 : 34) + (root.dispOn ? 9 : 0)
            // fixed-width slot between the shield and the side box: anything too
            // wide shrinks to fit instead of running into the box
            x: 490; width: 116; horizontalAlignment: Text.AlignHCenter
            fontSizeMode: Text.HorizontalFit; minimumPixelSize: 12
            height: 44; verticalAlignment: Text.AlignVCenter
            y: 181; opacity: root.intro
        }

        // RIGHT WING = LOGO: shows assets/wing_logo.png (your own image; a PNG with a
        // transparent background works best). Scaled to fit a 136 x 86 box, aspect
        // kept. Loaded only when the option is selected.
        Image {
            id: wingLogo
            visible: root.rightWing === 6 && root.logoTint === 0
            source: root.rightWing === 6 ? "assets/wing_logo.png" : ""
            x: 472; y: 146; width: 136; height: 86      // full width between the gear shield and the side box
            fillMode: Image.PreserveAspectFit
            smooth: true; mipmap: true; antialiasing: true
            opacity: root.intro
        }
        ShaderEffect {   // tinted copy: the image's alpha filled with one colour (core QtQuick, no GraphicalEffects)
            visible: root.rightWing === 6 && root.logoTint !== 0 && wingLogo.status === Image.Ready
            width: wingLogo.paintedWidth; height: wingLogo.paintedHeight
            x: wingLogo.x + (wingLogo.width - width) / 2; y: wingLogo.y + (wingLogo.height - height) / 2
            opacity: root.intro
            property variant src: wingLogo
            property color tint: root.logoTint === 2 ? root.accent : root.fg
            fragmentShader: "
                varying highp vec2 qt_TexCoord0;
                uniform sampler2D src;
                uniform lowp vec4 tint;
                uniform lowp float qt_Opacity;
                void main() {
                    lowp float a = texture2D(src, qt_TexCoord0).a;
                    gl_FragColor = vec4(tint.rgb * a, a) * qt_Opacity;
                }"
        }

        // ===== four side gauges (chrome + content; slide in on power-up) =====
        Repeater {
            model: [
                { kind: "oilpress", bx: 12,  by: 184 },
                { kind: "oiltemp",  bx: 12,  by: 276 },
                { kind: "afr",      bx: 612, by: 184 },
                { kind: "coolant",  bx: 612, by: 276 }
            ]
            delegate: Item {
                id: cell
                width: 176; height: 84
                property bool   isRight: modelData.bx > 400
                x: modelData.bx + (isRight ? 1 : -1) * (1 - root.intro) * 110
                y: modelData.by
                opacity: root.intro * (1 - 0.30 * root.raceAmt)
                scale: 1 - 0.14 * root.raceAmt                       // RACE mode: shrink toward the screen edge
                transformOrigin: isRight ? Item.Right : Item.Left
                readonly property bool coldTag: modelData.kind === "oiltemp" && root.coldActive
                visible: root.selfTest || (root.gaugeShown(modelData.kind) && !root.peakOccupies(modelData.kind))
                property bool   warn:    !root.selfTest && root.gaugeWarn(modelData.kind)
                // engine-damage criticals flash (low oil pressure / coolant overtemp)
                property bool   critical: !root.selfTest
                                      && ((modelData.kind === "oilpress" && !root.engineOff && root.oilPressShown <= root.oilPressLow)
                                       || (modelData.kind === "coolant"  && root.watertemp >= root.coolantHigh))
                property real   frac:    root.selfTest ? (root.sweepFrac * (1 - root.settle) + root.gaugeFrac(modelData.kind) * root.settle) : root.gaugeFrac(modelData.kind)
                property string valStr:  root.gaugeVal(modelData.kind)
                property string unitStr: root.gaugeUnit(modelData.kind)

                Rectangle {   // panel
                    anchors.fill: parent; radius: 6
                    color: root.bgPanel
                    border.width: 2; border.color: cell.warn ? "#ff4a4a" : root.bgS(0.508, 29)
                }
                Rectangle {   // red wash that pulses while a critical is active
                    anchors.fill: parent; radius: 6; color: "#ff2a2a"
                    opacity: (cell.critical && root.blinkOn) ? 0.26 : 0
                    Behavior on opacity { NumberAnimation { duration: 260 } }
                    visible: opacity > 0.01
                }
                Rectangle {   // CITY MAP: card-style accent line along the top
                    visible: root.mapBg
                    x: 2; y: 2; width: parent.width - 4; height: 3
                    color: cell.warn ? "#ff4a4a" : root.accent
                }
                Rectangle {   // accent spine on the outer edge
                    visible: !root.mapBg
                    x: cell.isRight ? parent.width - 5 : 1; y: 12; width: 4; height: parent.height - 24
                    color: cell.warn ? "#ff4a4a" : root.accentInk
                }
                Text {   // label
                    text: root.gaugeLabel(modelData.kind) + (cell.coldTag ? "  COLD" : "")
                    color: cell.warn ? root.redSoft : (cell.coldTag ? (root.light ? "#1565c0" : "#5ab0ff") : root.accentInk)
                    font.family: root.dispFont; font.bold: root.dispBold; font.pixelSize: root.dispOn ? 17 : 13; font.letterSpacing: 1
                    x: cell.isRight ? (parent.width - 16 - width) : 16; y: 7
                }
                Text {   // value
                    id: gVal
                    text: cell.valStr
                    color: cell.warn ? "#ff5050" : root.fg
                    font.family: root.dispFont; font.bold: root.dispBold; font.pixelSize: root.dispOn ? 44 : 34
                    x: cell.isRight ? (gUnit.visible ? (gUnit.x - width - 6) : (parent.width - 16 - width)) : 16; y: root.dispOn ? 18 : 22
                }
                Text {   // unit
                    id: gUnit
                    visible: cell.unitStr !== ""
                    text: cell.unitStr; color: root.fgDim
                    font.family: root.menuFont; font.bold: true; font.pixelSize: 14
                    x: cell.isRight ? (parent.width - 16 - width) : (gVal.x + gVal.width + 8); y: 42
                }
                Rectangle { x: 16; y: 70; width: 144; height: 8; color: root.bgS(0.242, 15) }  // bar track
                Rectangle {   // bar fill (low..high): green in band, red out of band
                    x: 16; y: 70; height: 8
                    width: cell.frac > 0 ? Math.max(6, 144 * cell.frac) : 0
                    Behavior on width { enabled: !root.selfTest; SmoothedAnimation { velocity: 260 } }
                    color: cell.warn ? "#ff3b30" : root.lotusGreen
                }
                Repeater {   // notches at 25 / 50 / 75 %
                    model: 3
                    Rectangle { x: 16 + 36 * (index + 1) - 1; y: 70; width: 2; height: 8; color: root.bgS(0.117, 4) }
                }
            }
        }

        // ===== speed streaks: lines in the wings that lengthen with road speed =====
        Repeater {
            model: 8
            Rectangle {
                readonly property bool rhs:   index >= 4
                readonly property int  i:     index % 4
                readonly property real frac:  Math.max(0, Math.min(1, root.speed / 240))
                height: 2; antialiasing: true
                width: frac * 118 * (1 - i * 0.2)
                Behavior on width { SmoothedAnimation { velocity: 140 } }
                color: (i % 2) ? root.lotusGreen : root.accent
                opacity: (root.fxStreaks && width > 2) ? (0.22 + 0.5 * frac) * root.intro : 0
                visible: opacity > 0.01
                x: rhs ? 482 : 318 - width
                y: 262 + i * 19
                transformOrigin: rhs ? Item.Left : Item.Right
                rotation: rhs ? 16 : -16
            }
        }

        // ===== accel / brake bar: centre-out, green right = accelerating, red left = braking =====
        Item {
            visible: root.fxAccel && !root.selfTest
            opacity: root.intro
            Rectangle { x: 300; y: 349; width: 200; height: 5; color: root.bgS(0.242, 15) }
            Rectangle {
                y: 349; height: 5
                width: Math.min(100, Math.abs(root.accelG) * 100)
                Behavior on width { SmoothedAnimation { velocity: 400 } }
                x: root.accelG >= 0 ? 400 : 400 - width
                color: root.accelG >= 0 ? root.lotusGreen : "#ff3b30"
            }
            Rectangle { x: 399; y: 346; width: 2; height: 11; color: root.fg2 }
        }

        // ===== critical warning banner (slides in from the left, holds, slides out) =====
        Item {
            x: root.bannerX; y: 268; width: 800; height: 62
            visible: bannerAnim.running
            Rectangle { anchors.fill: parent; color: "#e6c01010" }
            Rectangle { width: parent.width; height: 3; color: "#ffffff" }
            Rectangle { width: parent.width; height: 3; y: parent.height - 3; color: "#ffffff" }
            Text {
                anchors.centerIn: parent
                text: "\u26A0  " + root.bannerText + "  \u26A0"
                color: root.blinkOn ? "#ffffff" : "#ffd0d0"
                font.family: root.menuFont; font.bold: true; font.pixelSize: 32; font.letterSpacing: 3
            }
        }

        // ===== PEAK card (takes over a corner slot when SHOW PEAK GAUGE is on) =====
        Item {
            id: peakCard
            x: root.peakX; y: root.peakY; width: 176; height: 84
            visible: root.showPeak && !root.selfTest    // self-test runs the gauge sweep in this slot; PEAK takes over after
            Rectangle {
                anchors.fill: parent; radius: 6
                color: root.bgPanel; border.width: 2; border.color: root.bgS(0.508, 29)
            }
            Rectangle { visible: root.mapBg; x: 2; y: 2; width: parent.width - 4; height: 3; color: root.accent }
            Rectangle { x: root.peakX > 400 ? parent.width - 5 : 1; y: 12; width: 4; height: parent.height - 24; color: root.lotusGreen }
            Text {
                text: "PEAK"; color: root.accentInk
                font.family: root.dispFont; font.bold: root.dispBold; font.pixelSize: root.dispOn ? 17 : 13; font.letterSpacing: 1
                x: 16; y: 7
            }
            Column {                                 // one row per enabled peak metric; font auto-scales to fit
                x: 16; y: root.peakColY; width: 148; spacing: 1
                Repeater {
                    model: root.peakRows
                    delegate: Item {
                        width: 148; height: root.peakRowH
                        Text {
                            text: modelData.label; color: root.fgDim
                            font.family: root.menuFont; font.bold: true; font.pixelSize: root.peakFont
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                            width: 60; fontSizeMode: Text.HorizontalFit; minimumPixelSize: 8
                        }
                        Text {
                            text: modelData.text; color: root.fg
                            font.family: root.menuFont; font.bold: true; font.pixelSize: root.peakFont
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignRight; width: 84
                            fontSizeMode: Text.HorizontalFit; minimumPixelSize: 9
                        }
                    }
                }
            }
        }

        // ===== battery readout (bottom bar, left) =====
        Item {
            id: bat
            property bool  warn: root.batteryShown < root.batteryLow || root.batteryShown > root.batteryHigh
            property color col:  (!root.selfTest && warn) ? "#ff5050" : root.accentInk
            readonly property real realLvl: Math.max(0, Math.min(1, (root.batteryShown - root.batteryLow)
                                 / Math.max(0.1, root.batteryHigh - root.batteryLow)))
            property real  lvl:  root.selfTest ? (root.sweepFrac * (1 - root.settle) + realLvl * root.settle) : realLvl
            Rectangle { x: 18; y: 378; width: 30; height: 20; color: "transparent"
                        border.color: bat.col; border.width: 2 }           // body
            Rectangle { x: 48; y: 384; width: 3;  height: 8;  color: bat.col }   // nub
            Rectangle { x: 20; y: 380; width: 26 * bat.lvl; height: 16; color: bat.col }  // level
            Text {
                id: vText
                text: root.batteryShown.toFixed(1) + "V"
                color: (!root.selfTest && bat.warn) ? root.redSoft : root.fg
                font.family: root.dispFont; font.bold: root.dispBold; font.italic: true; font.pixelSize: root.dispOn ? 36 : 28
                x: 62; y: 387 - height / 2 - 3
            }
            Image {   // SERVICE wrench, right of the voltage. Hidden (not dimmed)
                      // unless the SERVICE bit (0x400000) is tripped.
                visible: root.selfTest || (root.inputs & 0x400000) !== 0
                source: "assets/service.png"
                height: 26
                width: implicitHeight > 0 ? 26 * implicitWidth / implicitHeight : 22
                fillMode: Image.PreserveAspectFit; smooth: true; antialiasing: true
                x: vText.x + vText.width + 16
                y: 388 - height / 2
            }
        }

        // ===== fuel bar (bottom bar, right): 12 segments =====
        Rectangle { x: 622; y: 378; width: 160; height: 20; color: root.bgS(0.192, 10) }   // track bg
        Repeater {
            model: 12
            delegate: Rectangle {
                x: 625 + index * 13; y: 381; width: 10; height: 14
                readonly property bool low: !root.selfTest && root.fuelLevel < root.fuelLow
                color: (index < Math.round(root.fuelBarFrac * 12))
                       ? (low ? "#ff4444" : root.lotusGreen)
                       : root.bgS(0.292, 18)
                opacity: (low && !root.blinkOn && index < Math.round(root.fuelBarFrac * 12)) ? 0.45 : 1   // low fuel pulses
                Behavior on opacity { NumberAnimation { duration: 260 } }
            }
        }

        // ===== odo / trip: lower-right normally; when the mode buttons are
        //       hidden, move up into the freed button space (right-aligned) =====
        Text {
            text: "ODO " + Math.round(root.odometer * root.distFactor) + root.distUnit
            color: root.fg2; font.family: root.menuFont; font.bold: true; font.pixelSize: 13
            x: 782 - width; y: (root.showModeButtons ? 457 : 424) - height / 2 - 1
        }
        Text {
            text: "TRIP " + Math.round(root.tripmeter * root.distFactor) + root.distUnit
            color: root.fg2; font.family: root.menuFont; font.bold: true; font.pixelSize: 13
            x: 782 - width; y: (root.showModeButtons ? 471 : 438) - height / 2 - 1
        }
    }


    // ====================================================================
    //  TELLTALES — icon set (assets/*.png), lit from inputsdata bits
    // ====================================================================
    Timer { interval: 420; repeat: true; running: true
            onTriggered: root.blinkOn = !root.blinkOn }
    // Battery readout debounce: raw volts jitter ~0.02 V and flip the shown tenth
    // (14.1<->14.2) every frame, reading as flicker. Only move the displayed value
    // once the live reading has drifted clearly past it (0.08 V deadband), sampled
    // a few times a second.
    Timer {
        interval: 400; repeat: true; running: true
        onTriggered: {
            if (root.batteryShown === 0 || Math.abs(root.battery - root.batteryShown) >= 0.08)
                root.batteryShown = root.battery;
        }
    }

    Image {   // fuel pump icon: white (fuel.png) normally, red warning
              // (fuel_level_warning.png) once the level drops below FUEL LOW
        source: root.fuelLevel < root.fuelLow ? "assets/fuel_level_warning.png"
                                              : (root.light ? "assets/fuel_dark.png" : "assets/fuel.png")
        x: 590; y: 366 + 22 - height/2; height: 20
        fillMode: Image.PreserveAspectFit; smooth: true
        opacity: root.fuelLevel < root.fuelLow ? 1.0 : 0.85
    }

    Row {   // telltale row
        x: 28; y: 417; spacing: 12
        Repeater {
            model: [
                { src: "high_beam",            bit: 0x10 },
                { src: "sidelight",            bit: 0x800 },     // sidelights (green)
                { src: "rear_fog",             bit: 0x08 },      // rear fog (amber)
                { src: "brake_warning",        bit: 0x8000100 },   // brake | handbrake
                { src: "oil_pressure_warning", bit: 0x200 },
                { src: "battery_warning",      bit: 0x02 },
                { src: "seatbelt_warning",     bit: 0x400 },
                { src: "abs_warning",          bit: 0x20000 },
                { src: "tc_warning",           bit: 0x10000 },    // traction control (amber)
                { src: "mil_warning",          bit: 0x40000 },
                { src: "airbag_warning",       bit: 0x8000 },
                { src: "door_open",            bit: 0x4000 }
            ]
            Item {
                id: ttCell
                height: 26
                width: ttImg.width
                readonly property bool isTc:  modelData.src === "tc_warning"
                readonly property bool tcOff: (root.inputs & 0x10000000) !== 0   // TC OFF bit
                Image {
                    id: ttImg
                    source: "assets/" + modelData.src + ".png"
                    height: 26
                    // Size to the glyph's true width (capped at 40) so the Row
                    // gives every icon the same 12px gap.
                    width: Math.min(40, implicitHeight > 0 ? 26 * implicitWidth / implicitHeight : 36)
                    fillMode: Image.PreserveAspectFit
                    smooth: true; antialiasing: true
                    // lit when its bit is set; the TC symbol also lights when TC
                    // is switched OFF, so the OFF tag sits on a lit icon
                    opacity: (root.selfTest || (root.inputs & modelData.bit) || (ttCell.isTc && ttCell.tcOff)) ? 1.0 : 0.22
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                }
                Rectangle {   // dark backing so "OFF" reads over the amber symbol
                    visible: ttCell.isTc && ttCell.tcOff
                    anchors.centerIn: ttImg
                    width: offTxt.implicitWidth + 4; height: offTxt.implicitHeight + 1; radius: 2
                    color: "#000000"; opacity: 0.6
                }
                Text {   // small "OFF" across the traction icon when TC is disabled
                    id: offTxt
                    visible: ttCell.isTc && ttCell.tcOff
                    anchors.centerIn: ttImg
                    text: "OFF"; color: "#ffffff"
                    font.family: root.menuFont; font.bold: true; font.pixelSize: 9
                }
            }
        }
    }

    // ECU ASCII status line (CAN canasciidata), lower-left below the telltales.
    // This is a cycling status line: the ECU rotates DISTINCT messages through it
    // (FAULT, TPMS, LTC, SLIP%, ...) and also flashes misaligned fragments
    // ("AULT FAULT"), lone partials ("LT", single letters) and empty pulses.
    // Pipeline: (1) canAsciiStr collapses each value's own repetition/partials;
    // (2) a 120 ms settle accepts a value only after it holds steady that long, so
    // single-frame blips never reach the screen while a message the ECU rests on
    // shows. Each settled message REPLACES the previous (no accumulation). An empty
    // value arms a 3 s timer; 3 s of continuous quiet blanks the line.
    // (3) Nuisance pattern: "TPMS" followed by a (repeating) "FAULT" is ONE occurrence
    // -- the FAULT keeps re-showing until the next TPMS. Occurrences are tallied
    // cumulatively (repeats or other text in between do NOT reset the count). After
    // canAsciiSuppressAfter occurrences this power cycle, the whole TPMS fault latches
    // off: the "TPMS" and the FAULTs that belong to it (the repeating "FAULT FAULT")
    // stop showing for the session. A FAULT that is NOT in a TPMS-fault context (no
    // preceding TPMS, or after other text such as "OIL FAULT" / "LTC") still shows.
    // Latch lives in memory only -> a power cycle restores it.
    Text {
        id: canAsciiText
        property string pending: root.canAsciiStr    // latest collapsed value
        property int canAsciiPairs: 0                 // TPMS->FAULT occurrences this power cycle (cumulative)
        property bool canAsciiAwaitFault: false       // last settled message was TPMS (next FAULT counts once)
        property bool canAsciiInFault: false          // inside a TPMS-fault context (its FAULTs repeat)
        property bool canAsciiHushed: false           // TPMS fault latched off for the session
        readonly property int canAsciiSuppressAfter: 5  // hush after this many TPMS->FAULT occurrences (0 = never)
        readonly property int canAsciiDwellMs: 900      // min ms a committed message holds before a non-higher-severity one may replace it
        onPendingChanged: canAsciiSettle.restart()    // debounce: ignore sub-120 ms blips
        visible: text.length > 0
        text: ""
        x: 28; y: 451
        width: 580; elide: Text.ElideRight
        color: root.light ? "#9a5f00" : "#ffcf6b"                              // amber ECU message
        font.family: root.menuFont; font.bold: true; font.pixelSize: 16
        Timer {
            id: canAsciiSettle
            interval: 120; repeat: false
            onTriggered: {
                var c = canAsciiText.pending;
                if (!c) {
                    canAsciiClearTimer.restart();             // empty -> arm blank
                } else {
                    var show = c;
                    if (c === "TPMS") {
                        if (canAsciiText.canAsciiSuppressAfter > 0
                            && canAsciiText.canAsciiPairs >= canAsciiText.canAsciiSuppressAfter)
                            canAsciiText.canAsciiHushed = true;          // enough occurrences -> latch off
                        canAsciiText.canAsciiAwaitFault = true;          // a FAULT may follow
                        canAsciiText.canAsciiInFault = true;             // entering the TPMS-fault context
                        if (canAsciiText.canAsciiHushed) show = "";
                    } else if (c === "FAULT") {
                        if (canAsciiText.canAsciiAwaitFault) {           // first FAULT after a TPMS = one occurrence
                            canAsciiText.canAsciiAwaitFault = false;
                            if (!canAsciiText.canAsciiHushed) canAsciiText.canAsciiPairs += 1;
                        }
                        if (canAsciiText.canAsciiHushed && canAsciiText.canAsciiInFault) show = "";   // hush repeating TPMS-fault FAULT
                        // a FAULT outside a TPMS-fault context keeps showing
                    } else {
                        canAsciiText.canAsciiAwaitFault = false;
                        canAsciiText.canAsciiInFault = false;            // other text ends the TPMS-fault context
                    }
                    // If the new value is just a space-stripped rotation of what is
                    // already on screen (host re-sent a no-separator repeat that the
                    // collapse reordered, e.g. "7% Slip" -> "Slip7%"), keep the version
                    // already shown rather than swapping to the reordered one.
                    if (show && canAsciiText.text && show !== canAsciiText.text
                        && root.canAsciiSameRotation(show, canAsciiText.text)) show = canAsciiText.text;
                    // Min on-screen dwell + severity hold (one gate). A fault-class
                    // message (sev 2) interrupts at once -- whether it replaces info
                    // or another fault -- so the TPMS/FAULT path is unchanged. Anything
                    // else (info) waits until the showing message has had its dwell, so
                    // a fast ECU rotation stays readable. Severity is only info=1 /
                    // fault=2 here, so "interrupt" reduces to "candidate is a fault".
                    // canAsciiDwell fires at dwell-end and re-runs this settle.
                    if (show && canAsciiText.text && show !== canAsciiText.text
                        && root.canAsciiSeverity(show) !== 2 && canAsciiDwell.running)
                        return;                              // hold current message through its dwell
                    canAsciiClearTimer.stop();
                    if (show !== canAsciiText.text) {
                        canAsciiText.text = show;
                        if (show) canAsciiDwell.restart(); else canAsciiDwell.stop();
                    }
                }
            }
        }
        Timer {
            id: canAsciiClearTimer
            interval: 3000; repeat: false
            onTriggered: { canAsciiText.text = ""; canAsciiText.canAsciiAwaitFault = false; canAsciiText.canAsciiInFault = false; }   // quiet ends the context
        }
        Timer {                                          // minimum on-screen dwell for a committed message
            id: canAsciiDwell
            interval: canAsciiText.canAsciiDwellMs; repeat: false
            onTriggered: canAsciiSettle.restart()        // re-evaluate the latest pending now the dwell elapsed
        }
    }

    Rectangle {   // RACE MODE button
        x: 636; y: 414; width: 72; height: 32; radius: 5
        visible: root.showModeButtons
        color: root.tRace ? "#2a1414" : root.bgS(0.2, 8)
        border.color: root.tRace ? "#ff5555" : root.bgS(0.508, 29); border.width: 1
        Column {
            anchors.centerIn: parent; spacing: 0
            Text { text: "RACE"; anchors.horizontalCenter: parent.horizontalCenter
                   color: root.tRace ? "#ff6666" : root.fgDim; font.family: root.menuFont; font.bold: true; font.pixelSize: 13 }
            Text { text: "MODE"; anchors.horizontalCenter: parent.horizontalCenter
                   color: root.tRace ? "#ff6666" : root.fgDim; font.family: root.menuFont; font.pixelSize: 8 }
        }
    }

    Rectangle {   // SPORT MODE button (inputsdata 0x1000000)
        x: 714; y: 414; width: 72; height: 32; radius: 5
        visible: root.showModeButtons
        color: root.tSport ? "#2a2608" : root.bgS(0.2, 8)
        border.color: root.tSport ? root.accent : root.bgS(0.508, 29); border.width: 1
        Column {
            anchors.centerIn: parent; spacing: 0
            Text { text: "SPORT"; anchors.horizontalCenter: parent.horizontalCenter
                   color: root.tSport ? root.accent : root.fgDim; font.family: root.menuFont; font.bold: true; font.pixelSize: 13 }
            Text { text: "MODE"; anchors.horizontalCenter: parent.horizontalCenter
                   color: root.tSport ? root.accent : root.fgDim; font.family: root.menuFont; font.pixelSize: 8 }
        }
    }

    Image {   // left indicator (mirrors the flasher relay)
        source: "assets/left_indicator.png"
        x: 36; y: 18; height: 50; fillMode: Image.PreserveAspectFit
        smooth: true
        visible: root.tLeftActive
    }
    Image {   // right indicator
        source: "assets/right_indicator.png"
        x: 718; y: 18; height: 50; fillMode: Image.PreserveAspectFit
        smooth: true
        visible: root.tRightActive
    }
    // ---- screen-edge shift strobe (FX: EDGE SHIFT FLASH): accent bars down both
    //      edges that flash at the shift point — readable in peripheral vision
    Repeater {
        model: [ { x: 0, w: 12, o: 1.0 }, { x: 12, w: 14, o: 0.35 }, { x: 788, w: 12, o: 1.0 }, { x: 774, w: 14, o: 0.35 } ]
        Rectangle {
            x: modelData.x; y: 0; width: modelData.w; height: 366
            // SUNSET: alternating red / blue (left and right swap each blink)
            color: root.sunset ? (((modelData.x < 400) === root.blinkOn) ? "#ff2d55" : "#2f6bff") : root.accent
            opacity: (root.fxEdge && root.overrev && (root.blinkOn || root.sunset)) ? modelData.o : 0
            Behavior on opacity { NumberAnimation { duration: 70 } }
            visible: opacity > 0.01
        }
    }
    }   // end dashShift
        // ---- NIGHTLIGHT dimmer: inside dashView so the live preview shows it,
        //      but outside dashShift so V-SHIFT does not move it (full coverage)
        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: root.nightlight / 100 * 0.7
            visible: root.nightlight > 0
        }
    }   // ---- end dashView (live-preview source) --------------------------

    // =======================================================================
    //  SETTINGS — config file, D-pad, and the scrolling menu (single file)
    // =======================================================================
    // Config location is resolved at startup (resolveCfgPath): some IC7 builds
    // use /opt/Garw_IC7/..., others /opt/IC7/.... cfgPath holds the resolved path;
    // cfgCandidates is the search order (first existing config wins; on a fresh
    // unit the first directory that accepts a write wins).
    property string cfgPath: "/opt/IC7/screen_configs/hethelrace_config.txt"
    readonly property var cfgCandidates: [
        "/opt/Garw_IC7/screen_configs/hethelrace_config.txt",
        "/opt/IC7/screen_configs/hethelrace_config.txt"
    ]
    FileIO {
        id: cfg
        // IC7 maps this to <dash>/screen_configs/hethelrace_config.txt.
        source: root.cfgPath
        onError: console.log("HethelRace FileIO: " + msg)
    }


    // config line order (one value per line). Keep load + save identical.
    // Returns true if a usable config was read, false if missing/empty.
    //
    // IC7 FileIO READ CONTRACT (verified on hardware): the reader returns ONE
    // line per open, and only the FIRST readopenfile() after each open works;
    // the index selects the line. So to read line i you must:
    //     openforreading(); var s = readopenfile(i); close();
    // i.e. re-open before every single line. Reading several lines in one open
    // returns only the first; that was the long-standing "won't read" bug.
    function rline(i) {
        var s = "";
        try { cfg.openforreading(); s = cfg.readopenfile(i); cfg.close(); }
        catch (e) { console.log("HethelRace: read line " + i + " failed (" + e + ")"); }
        return s;
    }
    // Resolve cfgPath to the directory that exists on this unit (see cfgCandidates).
    // Prefer a candidate that already holds a readable config; otherwise pick the
    // first whose directory accepts a write (the write only sticks where the dir
    // exists). Runs once at startup, before loadConfig.
    function resolveCfgPath() {
        var i, s;
        for (i = 0; i < root.cfgCandidates.length; i++) {
            root.cfgPath = root.cfgCandidates[i];
            s = rline(0);
            if (s !== "" && s !== undefined && s !== null) return;   // existing config here
        }
        for (i = 0; i < root.cfgCandidates.length; i++) {
            root.cfgPath = root.cfgCandidates[i];
            saveConfig();                                            // seed defaults
            s = rline(0);
            if (s !== "" && s !== undefined && s !== null) return;   // write stuck -> dir exists
        }
        root.cfgPath = root.cfgCandidates[root.cfgCandidates.length - 1];   // fallback
    }
    function loadConfig() {
        function pI(s, def) { return (s !== "" && s !== undefined && s !== null) ? parseInt(s)   : def; }
        function pF(s, def) { return (s !== "" && s !== undefined && s !== null) ? parseFloat(s) : def; }
        // Config is "key=value" lines (any order, hand-editable). Read them into a
        // map; if none are found, fall back to the old positional format once so an
        // existing config migrates without losing settings (next save is key=value).
        var map = {}; var any = false;
        // IC7 FileIO is one-line-per-open (only the first readopenfile after each
        // open returns its line), so read each line via rline() -- which re-opens
        // per line -- instead of multiple reads inside one open. Reading in a single
        // open only returns line 0 on the device, dropping every other setting.
        for (var i = 0; i < 200; i++) {
            var ln = rline(i);
            if (ln === "" || ln === undefined || ln === null) break;
            var eq = String(ln).indexOf("=");
            if (eq > 0) { map[String(ln).substring(0, eq).trim()] = String(ln).substring(eq + 1).trim(); any = true; }
        }

        if (!any) {   // old positional format (or no config at all)
            var s0 = rline(0);
            if (s0 === "" || s0 === undefined || s0 === null || isNaN(parseFloat(s0))) return false;
            root.red=pI(rline(0),root.red); root.green=pI(rline(1),root.green); root.blue=pI(rline(2),root.blue);
            root.rpmredline=pI(rline(3),root.rpmredline); root.rpmmax=pI(rline(4),root.rpmmax); root.rpmDamp=pI(rline(5),root.rpmDamp);
            root.speedunits=pI(rline(6),root.speedunits); root.distunits=pI(rline(7),root.distunits);
            root.coolantHigh=pF(rline(8),root.coolantHigh); root.coolantLow=pF(rline(9),root.coolantLow); root.tempunits=pI(rline(10),root.tempunits);
            root.fuelHigh=pI(rline(11),root.fuelHigh); root.fuelLow=pI(rline(12),root.fuelLow); root.fuelDamp=pI(rline(13),root.fuelDamp);
            root.oilTempHigh=pF(rline(14),root.oilTempHigh); root.oilTempLow=pF(rline(15),root.oilTempLow); root.oilTempUnits=pI(rline(16),root.oilTempUnits);
            root.oilPressHigh=pF(rline(17),root.oilPressHigh); root.oilPressLow=pF(rline(18),root.oilPressLow); root.oilPressUnits=pI(rline(19),root.oilPressUnits);
            root.batteryHigh=pF(rline(20),root.batteryHigh); root.batteryLow=pF(rline(21),root.batteryLow);
            root.afrHigh=pF(rline(22),root.afrHigh); root.afrLow=pF(rline(23),root.afrLow); root.nightlight=pI(rline(24),root.nightlight);
            root.afrSource=pI(rline(25),root.afrSource); root.placementSwap=pI(rline(26),root.placementSwap?1:0)!==0;
            root.hideTachNums=pI(rline(27),root.hideTachNums?1:0)!==0; root.hideShiftLights=pI(rline(28),root.hideShiftLights?1:0)!==0;
            root.showPeakGauge=pI(rline(29),root.showPeakGauge?1:0)!==0; root.peakGaugePosition=pI(rline(30),root.peakGaugePosition);
            root.peakShowRpm=pI(rline(31),root.peakShowRpm?1:0)!==0; root.peakShowSpeed=pI(rline(32),root.peakShowSpeed?1:0)!==0;
            root.peakShowAfr=pI(rline(33),root.peakShowAfr?1:0)!==0; root.peakShowOilTemp=pI(rline(34),root.peakShowOilTemp?1:0)!==0;
            root.peakShowOilPress=pI(rline(35),root.peakShowOilPress?1:0)!==0; root.peakShowCoolant=pI(rline(36),root.peakShowCoolant?1:0)!==0;
            root.showModeButtons=pI(rline(37),root.showModeButtons?1:0)!==0; root.vShift=pI(rline(38),root.vShift);
            return true;
        }

        function g(k){ return map.hasOwnProperty(k) ? map[k] : ""; }
        root.red=pI(g("red"),root.red); root.green=pI(g("green"),root.green); root.blue=pI(g("blue"),root.blue);
        root.rpmredline=pI(g("rpmredline"),root.rpmredline); root.rpmmax=pI(g("rpmmax"),root.rpmmax); root.rpmDamp=pI(g("rpmDamp"),root.rpmDamp);
        root.speedunits=pI(g("speedunits"),root.speedunits); root.distunits=pI(g("distunits"),root.distunits);
        root.coolantHigh=pF(g("coolantHigh"),root.coolantHigh); root.coolantLow=pF(g("coolantLow"),root.coolantLow); root.tempunits=pI(g("tempunits"),root.tempunits);
        root.fuelHigh=pI(g("fuelHigh"),root.fuelHigh); root.fuelLow=pI(g("fuelLow"),root.fuelLow); root.fuelDamp=pI(g("fuelDamp"),root.fuelDamp);
        root.oilTempHigh=pF(g("oilTempHigh"),root.oilTempHigh); root.oilTempLow=pF(g("oilTempLow"),root.oilTempLow); root.oilTempUnits=pI(g("oilTempUnits"),root.oilTempUnits);
        root.oilPressHigh=pF(g("oilPressHigh"),root.oilPressHigh); root.oilPressLow=pF(g("oilPressLow"),root.oilPressLow); root.oilPressUnits=pI(g("oilPressUnits"),root.oilPressUnits);
        root.batteryHigh=pF(g("batteryHigh"),root.batteryHigh); root.batteryLow=pF(g("batteryLow"),root.batteryLow);
        root.afrHigh=pF(g("afrHigh"),root.afrHigh); root.afrLow=pF(g("afrLow"),root.afrLow); root.nightlight=pI(g("nightlight"),root.nightlight);
        root.afrSource=pI(g("afrSource"),root.afrSource); root.placementSwap=pI(g("placementSwap"),root.placementSwap?1:0)!==0;
        root.hideTachNums=pI(g("hideTachNums"),root.hideTachNums?1:0)!==0; root.hideShiftLights=pI(g("hideShiftLights"),root.hideShiftLights?1:0)!==0;
        root.showPeakGauge=pI(g("showPeakGauge"),root.showPeakGauge?1:0)!==0; root.peakGaugePosition=pI(g("peakGaugePosition"),root.peakGaugePosition);
        root.peakShowRpm=pI(g("peakShowRpm"),root.peakShowRpm?1:0)!==0; root.peakShowSpeed=pI(g("peakShowSpeed"),root.peakShowSpeed?1:0)!==0;
        root.peakShowAfr=pI(g("peakShowAfr"),root.peakShowAfr?1:0)!==0; root.peakShowOilTemp=pI(g("peakShowOilTemp"),root.peakShowOilTemp?1:0)!==0;
        root.peakShowOilPress=pI(g("peakShowOilPress"),root.peakShowOilPress?1:0)!==0; root.peakShowCoolant=pI(g("peakShowCoolant"),root.peakShowCoolant?1:0)!==0;
        root.showModeButtons=pI(g("showModeButtons"),root.showModeButtons?1:0)!==0; root.vShift=pI(g("vShift"),root.vShift);
        root.barColours=clamp(pI(g("barColours"),root.barColours),0,2);
        for (var fi = 0; fi < root.fxKeys.length; fi++) { var fk = root.fxKeys[fi]; root[fk] = pI(g(fk), root[fk] ? 1 : 0) !== 0; }
        root.launchRpm=pI(g("launchRpm"),root.launchRpm);
        root.bgRed=clamp(pI(g("bgRed"),root.bgRed),0,255); root.bgGreen=clamp(pI(g("bgGreen"),root.bgGreen),0,255); root.bgBlue=clamp(pI(g("bgBlue"),root.bgBlue),0,255);
        root.theme=clamp(pI(g("theme"),root.theme),0,3); root.neonFont=pI(g("neonFont"),root.neonFont?1:0)!==0;
        root.logoTint=clamp(pI(g("logoTint"),root.logoTint),0,2);
        root.rightWing=clamp(pI(g("rightWing"),root.rightWing),0,7);
        root.greenFrom=pI(g("greenFrom"),root.greenFrom); root.yellowFrom=pI(g("yellowFrom"),root.yellowFrom); root.redFrom=pI(g("redFrom"),root.redFrom);
        return true;
    }
    function saveConfig() {
        try {
            var a = [];
            a.push("red=" + root.red); a.push("green=" + root.green); a.push("blue=" + root.blue);
            a.push("rpmredline=" + root.rpmredline); a.push("rpmmax=" + root.rpmmax); a.push("rpmDamp=" + root.rpmDamp);
            a.push("speedunits=" + root.speedunits); a.push("distunits=" + root.distunits);
            a.push("coolantHigh=" + root.coolantHigh.toFixed(1)); a.push("coolantLow=" + root.coolantLow.toFixed(1)); a.push("tempunits=" + root.tempunits);
            a.push("fuelHigh=" + root.fuelHigh); a.push("fuelLow=" + root.fuelLow); a.push("fuelDamp=" + root.fuelDamp);
            a.push("oilTempHigh=" + root.oilTempHigh.toFixed(1)); a.push("oilTempLow=" + root.oilTempLow.toFixed(1)); a.push("oilTempUnits=" + root.oilTempUnits);
            a.push("oilPressHigh=" + root.oilPressHigh.toFixed(1)); a.push("oilPressLow=" + root.oilPressLow.toFixed(1)); a.push("oilPressUnits=" + root.oilPressUnits);
            a.push("batteryHigh=" + root.batteryHigh.toFixed(1)); a.push("batteryLow=" + root.batteryLow.toFixed(1));
            a.push("afrHigh=" + root.afrHigh.toFixed(2)); a.push("afrLow=" + root.afrLow.toFixed(2)); a.push("nightlight=" + root.nightlight);
            a.push("afrSource=" + root.afrSource); a.push("placementSwap=" + (root.placementSwap ? 1 : 0));
            a.push("hideTachNums=" + (root.hideTachNums ? 1 : 0)); a.push("hideShiftLights=" + (root.hideShiftLights ? 1 : 0));
            a.push("showPeakGauge=" + (root.showPeakGauge ? 1 : 0)); a.push("peakGaugePosition=" + root.peakGaugePosition);
            a.push("peakShowRpm=" + (root.peakShowRpm ? 1 : 0)); a.push("peakShowSpeed=" + (root.peakShowSpeed ? 1 : 0));
            a.push("peakShowAfr=" + (root.peakShowAfr ? 1 : 0)); a.push("peakShowOilTemp=" + (root.peakShowOilTemp ? 1 : 0));
            a.push("peakShowOilPress=" + (root.peakShowOilPress ? 1 : 0)); a.push("peakShowCoolant=" + (root.peakShowCoolant ? 1 : 0));
            a.push("showModeButtons=" + (root.showModeButtons ? 1 : 0)); a.push("vShift=" + root.vShift);
            a.push("theme=" + root.theme); a.push("neonFont=" + (root.neonFont ? 1 : 0)); a.push("bgRed=" + root.bgRed); a.push("bgGreen=" + root.bgGreen); a.push("bgBlue=" + root.bgBlue);
            a.push("barColours=" + root.barColours); a.push("greenFrom=" + root.greenFrom);
            a.push("yellowFrom=" + root.yellowFrom); a.push("redFrom=" + root.redFrom);
            for (var fi = 0; fi < root.fxKeys.length; fi++) a.push(root.fxKeys[fi] + "=" + (root[root.fxKeys[fi]] ? 1 : 0));
            a.push("launchRpm=" + root.launchRpm); a.push("rightWing=" + root.rightWing); a.push("logoTint=" + root.logoTint);
            cfg.open(); cfg.writetoopenfile(a.join("\n") + "\n"); cfg.close();
        } catch (e) { console.log("HethelRace: could not write config (" + e + ")"); }
    }
    // First run: if no config is found, write the current defaults so the file
    // exists (FileIO does not create it on a read).
    Component.onCompleted: {
        // Tell the host firmware that warnings are handled locally, so it does
        // NOT draw its own warning-light bar over the dash. Hardware-only flag
        // (the property is absent in the desktop sim), so the write is guarded.
        if (root.d) { try { root.d.DISABLE_WARNING_OVERLAY = "YES_WARNINGS_HANDLED_LOCALLY"; } catch (e) {} }
        resolveCfgPath();        // pick /opt/Garw_IC7 vs /opt/IC7 (whichever exists on this unit)
        if (!loadConfig())
            saveConfig();
        fuelDisplay = fuelNow();   // start the damped bar at the live level (no boot sweep)
        fuelFiltered = fuelDisplay;   // seed the trimmed-mean filter
        oilPressShown = oilpress;   // start oil pressure at live (boot self-test owns the boot sweep)
        bootSweep.start();    // power-on self-test sweep
        introAnim.start();    // gauges slide / fade in alongside it
        gearLast = gearLabel; maxPrev = maxTarget;
    }

    // ---- D-pad (inputsdata bits via root.inputs; udp_packetdata fallback) --
    function udp()    { return (root.d && root.d.udp_packetdata !== undefined) ? root.d.udp_packetdata : 0; }
    function dUp()    { return ((root.inputs & 0x20) !== 0)       || ((udp() & 0x01) !== 0); }
    function dDown()  { return ((root.inputs & 0x2000) !== 0)     || ((udp() & 0x02) !== 0); }
    function dLeft()  { return ((root.inputs & 0x20000000) !== 0) || ((udp() & 0x04) !== 0); }
    function dRight() { return ((root.inputs & 0x40000000) !== 0) || ((udp() & 0x08) !== 0); }

    // ---- menu model --------------------------------------------------------
    property bool menuOpen: false
    property int  sel: 0
    property int  settingsRev: 0      // bumped on every value change -> ListView value cells re-read
    property real pulse: 0
    property bool pUp: false
    property bool pDown: false
    property bool pLeft: false
    property bool pRight: false
    property int  upHold: 0
    property int  downHold: 0
    property bool upArmed: false      // hold-to-ramp arms only after release
    property bool downArmed: false

    // every navigable row: {k: key, label: shown text}. Order = on-screen order.
    readonly property var itemsAll: [
        { k: "shift",  label: "SHIFT RPM" },
        { k: "limit",  label: "RPM LIMIT" },
        { k: "rdamp",  label: "RPM DAMPING" },
        { k: "bcol",   label: "REV BAR COLOURS" },
        { k: "gfrom",  label: "GREEN FROM" },
        { k: "yfrom",  label: "YELLOW FROM" },
        { k: "rfrom",  label: "RED FROM" },
        { k: "theme",  label: "THEME" },
        { k: "nfont",  label: "NEON FONT" },
        { k: "red",    label: "RED" },
        { k: "green",  label: "GREEN" },
        { k: "blue",   label: "BLUE" },
        { k: "bgr",    label: "BG RED" },
        { k: "bgg",    label: "BG GREEN" },
        { k: "bgb",    label: "BG BLUE" },
        { k: "speed",  label: "SPEED UNIT" },
        { k: "dist",   label: "DIST UNIT" },
        { k: "chi",    label: "COOLANT HIGH" },
        { k: "clo",    label: "COOLANT LOW" },
        { k: "cun",    label: "COOLANT UNIT" },
        { k: "fhi",    label: "FUEL HIGH" },
        { k: "flo",    label: "FUEL LOW" },
        { k: "fdmp",   label: "FUEL DAMP" },
        { k: "othi",   label: "OIL TEMP HIGH" },
        { k: "otlo",   label: "OIL TEMP LOW" },
        { k: "otun",   label: "OIL TEMP UNIT" },
        { k: "ophi",   label: "OIL PRESS HIGH" },
        { k: "oplo",   label: "OIL PRESS LOW" },
        { k: "opun",   label: "OIL PRESS UNIT" },
        { k: "bhi",    label: "BATTERY HIGH" },
        { k: "blo",    label: "BATTERY LOW" },
        { k: "ahi",    label: "AFR HIGH" },
        { k: "alo",    label: "AFR LOW" },
        { k: "asrc",   label: "AFR SOURCE" },
        { k: "night",  label: "NIGHTLIGHT" },
        { k: "swap",   label: "RPM/SPEED SWAP" },
        { k: "rwing",  label: "RIGHT WING" },
        { k: "ltint",  label: "LOGO TINT" },
        { k: "pkon",   label: "SHOW PEAK GAUGE" },
        { k: "pkpos",  label: "PEAK POSITION" },
        { k: "pkrpm",  label: "PEAK: RPM" },
        { k: "pkspd",  label: "PEAK: SPEED" },
        { k: "pkafr",  label: "PEAK: AFR" },
        { k: "pkotm",  label: "PEAK: OIL TEMP" },
        { k: "pkopr",  label: "PEAK: OIL PRESS" },
        { k: "pkcol",  label: "PEAK: COOLANT" },
        { k: "pkrst",  label: "RESET PEAKS" },
        { k: "htn",    label: "HIDE TACH NUMS" },
        { k: "hsl",    label: "HIDE SHIFT LIGHTS" },
        { k: "mbtn",   label: "MODE BUTTONS" },
        { k: "vshift", label: "V-SHIFT" },
        { k: "fxSeq",      label: "FX: SEQ SHIFT LIGHTS" },
        { k: "fxEdge",     label: "FX: EDGE SHIFT FLASH" },
        { k: "fxRoll",     label: "FX: GEAR ROLL" },
        { k: "fxBloom",    label: "FX: REDLINE BLOOM" },
        { k: "fxLimiter",  label: "FX: LIMITER STUTTER" },
        { k: "fxLaunch",   label: "FX: LAUNCH MODE" },
        { k: "lrpm",       label: "LAUNCH RPM" },
        { k: "fxAccel",    label: "FX: ACCEL/BRAKE BAR" },
        { k: "fxStreaks",  label: "FX: SPEED STREAKS" },
        { k: "fxBest",     label: "FX: NEW-BEST FLASH" },
        { k: "fxRace",     label: "FX: RACE TAKEOVER" },
        { k: "fxBanner",   label: "FX: WARNING BANNER" },
        { k: "fxCold",     label: "FX: COLD REV LIMIT" },
        { k: "fxShutdown", label: "FX: SHUTDOWN SWEEP" },
        { k: "exit",   label: "EXIT" }
    ]
    // the PEAK: * picker rows appear only while SHOW PEAK GAUGE is on
    readonly property var peakItemKeys: ["pkrpm","pkspd","pkafr","pkotm","pkopr","pkcol","pkrst"]
    readonly property var items: itemsAll
    // a PEAK: * picker row is collapsed and skipped while SHOW PEAK GAUGE is off,
    // without changing the model identity (which would reset the selector to top)
    // the GREEN/YELLOW/RED FROM rows appear only while REV BAR COLOURS is ZONES
    readonly property var zoneItemKeys: ["gfrom","yfrom","rfrom"]
    function rowHidden(k) { return (!showPeakGauge && peakItemKeys.indexOf(k) !== -1)
                                || (barColours !== 1 && zoneItemKeys.indexOf(k) !== -1)
                                || (!fxLaunch && k === "lrpm")
                                || (rightWing !== 6 && k === "ltint")
                                || (!sunset && k === "nfont"); }
    function isFx(k) { return k.indexOf("fx") === 0; }
    readonly property var fxHelp: ({
        fxSeq:      "12 LEDs fill from both ends to the centre from 82% of SHIFT RPM, then flash. Off = the three rings.",
        fxEdge:     "Accent bars down both screen edges strobe at SHIFT RPM.",
        fxRoll:     "Gear digit rolls up on an upshift, down on a downshift. Off = pop.",
        fxBloom:    "The glow behind the bar widens and strengthens in the red zone.",
        fxLimiter:  "The last lit segments flicker when the revs reach RPM LIMIT.",
        fxLaunch:   "Stationary with revs over 2000: a target band on the bar, READY in the band, GO when you move.",
        fxAccel:    "Bar under the big readout: green right = accelerating, red left = braking (from road speed).",
        fxStreaks:  "Lines in the wings that lengthen with road speed.",
        fxBest:     "RIGHT WING max speed / max RPM count up and flash green on a new best; so does a best 0-60 time.",
        fxRace:     "RACE input on: the side gauges shrink back, the gear and rev bar grow.",
        fxBanner:   "Low oil pressure / coolant overtemp slide a red banner across the centre for 3 s.",
        fxCold:     "Until the oil reaches OIL TEMP LOW, a blue band marks a reduced rev ceiling that rises as it warms.",
        fxShutdown: "When the engine stops, the gauges slide out and back in."
    })
    // toggles + exit aren't hold-to-ramp; everything else is.
    readonly property var noRamp: ["nfont", "ltint", "theme", "bcol", "rwing", "speed", "dist", "cun", "otun", "opun", "asrc", "swap", "pkon", "pkpos", "pkrpm", "pkspd", "pkafr", "pkotm", "pkopr", "pkcol", "pkrst", "htn", "hsl", "mbtn", "exit"]
    function isRampable(k) { return noRamp.indexOf(k) === -1 && !isFx(k); }
    function helpText(k) {
        if (isFx(k)) return fxHelp[k];
        switch (k) {
        case "bgr": case "bgg": case "bgb": return "Background tint (0-255): backdrop, panels and borders. Default 0/120/74 = Lotus green; 0/0/0 = carbon grey. Not used by the SUNSET / CITY MAP themes.";
        case "theme": return "DARK: light text on a dark background. LIGHT: dark text on near-white. SUNSET: neon dusk with palms. CITY MAP: night street map with card panels. Both use star shift lights, a red/blue shift strobe and fixed colours.";
        case "nfont": return "Use the Pricedown display font for the gear, numbers and labels in the SUNSET / CITY MAP themes. OFF = the standard font.";
        case "ltint": return "Recolour the logo: OFF = as supplied, THEME = text colour (white on DARK, black on LIGHT), ACCENT = accent colour. For single-colour logos.";
        case "lrpm": return "Centre of the launch target band (\u00B1300 rpm).";
        case "rwing": return "Readout right of the gear: 0-100 km/h (0-60 mph) timer, fuel %, max speed, max RPM, session timer, peak g, a logo image (assets/wing_logo.png), or off.";
        case "shift": return "RPM where the redline / shift lights begin.";
        case "limit": return "Full-scale RPM at the top of the tach sweep.";
        case "rdamp": return "Needle smoothing (1 = sharp \u2192 10 = smooth).";
        case "bcol": return "ZONES: green, yellow, then red at the rpm set below. BLEND: green fading to the accent, red at SHIFT RPM. ACCENT: accent colour, red at SHIFT RPM.";
        case "gfrom": return "The bar is green from this rpm; below it, the accent colour. 0 = green from the start.";
        case "yfrom": return "The bar turns yellow from this rpm. Set it equal to RED FROM to leave yellow out.";
        case "rfrom": return "The bar turns red from this rpm to the end of the scale.";
        case "red": case "green": case "blue": return "Accent colour (0-255). Default 255/224/0 = Lotus yellow. Not used by the SUNSET / CITY MAP themes.";
        case "speed": return "Units for speed, odometer and trip.";
        case "dist": return "Distance units for ODO / TRIP.";
        case "chi": return "Coolant warns above this temperature.";
        case "clo": return "Coolant shown cold below this temperature.";
        case "cun": return "Coolant temperature units.";
        case "fhi": return "Fuel sender reading for a full tank.";
        case "flo": return "Low-fuel warning below this.";
        case "fdmp": return "Smooths the fuel reading.";
        case "othi": return "Oil-temperature warning above this.";
        case "otlo": return "Oil shown cold below this temperature.";
        case "otun": return "Oil-temperature units (or OFF).";
        case "ophi": return "Oil-pressure warning above this.";
        case "oplo": return "Low oil-pressure warning below this.";
        case "opun": return "Oil-pressure units (or OFF).";
        case "bhi": return "Battery warning above this voltage.";
        case "blo": return "Battery warning below this voltage.";
        case "ahi": return "AFR warning above this (lean).";
        case "alo": return "AFR warning below this (rich).";
        case "asrc": return "AFR readout: AFR, Lambda, or OFF.";
        case "night": return "Night-time dimming level.";
        case "swap": return "Put RPM (instead of SPEED) in the big readout under the gear.";
        case "htn": return "Hide the small numbers under the rev bar.";
        case "hsl": return "Hide the three shift lights above the rev bar.";
        case "mbtn": return "Show the RACE / SPORT mode buttons.";
        case "pkon": return "Show the PEAK (session-high) card.";
        case "pkpos": return "Which corner the PEAK card sits in.";
        case "pkrpm": case "pkspd": case "pkafr": case "pkotm": case "pkopr": case "pkcol":
            return "Include this reading on the PEAK card.";
        case "pkrst": return "Clear the stored session peaks.";
        case "vshift": return "Move the whole dash up / down for your seating height.";
        case "exit": return "Save all settings and close the menu.";
        }
        return "";
    }

    function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

    // dir = +1 (Up) / -1 (Down). Steps / clamps are chosen per setting.
    function applyValue(dir) {
        var k = items[sel].k;
        if (isFx(k)) { root[k] = !root[k]; root.settingsRev += 1; return; }
        switch (k) {
        case "lrpm":   root.launchRpm    = clamp(root.launchRpm + dir * 100, 2300, root.rpmmax - 300); break;
        case "rwing":  root.rightWing    = ((root.rightWing + dir) % 8 + 8) % 8; break;
        case "theme":  root.theme        = ((root.theme + dir) % 4 + 4) % 4; break;
        case "nfont":  root.neonFont     = !root.neonFont; break;
        case "ltint":  root.logoTint     = ((root.logoTint + dir) % 3 + 3) % 3; break;
        case "bgr":    root.bgRed        = clamp(root.bgRed   + dir * 5, 0, 255); break;
        case "bgg":    root.bgGreen      = clamp(root.bgGreen + dir * 5, 0, 255); break;
        case "bgb":    root.bgBlue       = clamp(root.bgBlue  + dir * 5, 0, 255); break;
        case "shift":  root.rpmredline   = clamp(root.rpmredline + dir * 100, 2000, root.rpmmax - 100); break;
        case "limit":  root.rpmmax       = clamp(root.rpmmax     + dir * 100, 4000, 12000); break;
        case "rdamp":  root.rpmDamp      = clamp(root.rpmDamp    + dir,        1,    10);    break;
        case "bcol":   root.barColours   = ((root.barColours + dir) % 3 + 3) % 3; break;
        // zone starts stay ordered: green <= yellow <= red <= RPM LIMIT
        case "gfrom":  root.greenFrom    = clamp(root.greenFrom  + dir * 100, 0, Math.min(root.yellowFrom, root.rpmmax)); break;
        case "yfrom":  root.yellowFrom   = clamp(root.yellowFrom + dir * 100, root.greenFrom, Math.min(root.redFrom, root.rpmmax)); break;
        case "rfrom":  root.redFrom      = clamp(root.redFrom    + dir * 100, root.yellowFrom, root.rpmmax); break;
        case "red":    root.red          = clamp(root.red        + dir * 5,    0,    255);   break;
        case "green":  root.green        = clamp(root.green      + dir * 5,    0,    255);   break;
        case "blue":   root.blue         = clamp(root.blue       + dir * 5,    0,    255);   break;
        case "speed":  root.speedunits   = (root.speedunits === 0) ? 1 : 0;   break;
        case "dist":   root.distunits    = (root.distunits  === 0) ? 1 : 0;   break;
        case "chi":    root.coolantHigh  = clamp(root.coolantHigh + dir * (root.tempunits === 1 ? 5/9 : 1), 60, 150);  break;
        case "clo":    root.coolantLow   = clamp(root.coolantLow  + dir * (root.tempunits === 1 ? 5/9 : 1), 0,  140);  break;
        case "cun":    root.tempunits    = ((root.tempunits + dir) % 3 + 3) % 3;    break;
        case "fhi":    root.fuelHigh     = clamp(root.fuelHigh + dir, 0, 100); break;
        case "flo":    root.fuelLow      = clamp(root.fuelLow  + dir, 0, 100); break;
        case "fdmp":   root.fuelDamp     = clamp(root.fuelDamp + dir, 0, 9);   break;
        case "othi":   root.oilTempHigh  = clamp(root.oilTempHigh + dir * (root.oilTempUnits === 1 ? 5/9 : 1), 0, 250); break;
        case "otlo":   root.oilTempLow   = clamp(root.oilTempLow  + dir * (root.oilTempUnits === 1 ? 5/9 : 1), 0, 250); break;
        case "otun":   root.oilTempUnits = ((root.oilTempUnits + dir) % 3 + 3) % 3; break;
        case "pkon":   root.showPeakGauge = !root.showPeakGauge; break;
        case "pkpos":  root.peakGaugePosition = ((root.peakGaugePosition - 1 + dir) % 4 + 4) % 4 + 1; break;
        case "pkrpm":  root.peakShowRpm      = !root.peakShowRpm;      break;
        case "pkspd":  root.peakShowSpeed    = !root.peakShowSpeed;    break;
        case "pkafr":  root.peakShowAfr      = !root.peakShowAfr;      break;
        case "pkotm":  root.peakShowOilTemp  = !root.peakShowOilTemp;  break;
        case "pkopr":  root.peakShowOilPress = !root.peakShowOilPress; break;
        case "pkcol":  root.peakShowCoolant  = !root.peakShowCoolant;  break;
        case "pkrst":  if (dir > 0) root.resetPeaks(); break;
        case "ophi":   root.oilPressHigh = clamp(root.oilPressHigh + dir * (root.oilPressUnits === 1 ? 1.45038 : 1), 0, 200); break;
        case "oplo":   root.oilPressLow  = clamp(root.oilPressLow  + dir * (root.oilPressUnits === 1 ? 1.45038 : 1), 0, 200); break;
        case "opun":   root.oilPressUnits= ((root.oilPressUnits + dir) % 3 + 3) % 3; break;
        case "bhi":    root.batteryHigh  = clamp(root.batteryHigh + dir * 0.1, 0, 20); break;
        case "blo":    root.batteryLow   = clamp(root.batteryLow  + dir * 0.1, 0, 20); break;
        case "ahi":    root.afrHigh      = clamp(root.afrHigh + dir * (root.afrSource === 0 ? 0.1/14.7 : 0.01), 0.5, 1.5); break;
        case "alo":    root.afrLow       = clamp(root.afrLow  + dir * (root.afrSource === 0 ? 0.1/14.7 : 0.01), 0.5, 1.5); break;
        case "asrc":   root.afrSource    = ((root.afrSource + dir) % 3 + 3) % 3; break;
        case "night":  root.nightlight   = clamp(root.nightlight + dir * 5, 0, 100); break;
        case "swap":   root.placementSwap = !root.placementSwap; break;
        case "htn":    root.hideTachNums  = !root.hideTachNums;  break;
        case "hsl":    root.hideShiftLights = !root.hideShiftLights; break;
        case "mbtn":   root.showModeButtons = !root.showModeButtons; break;
        case "vshift": root.vShift = clamp(root.vShift + dir * 2, -40, 40); break;
        case "exit":   if (dir > 0) { saveConfig(); closeMenu(); return; } break;
        }
        root.settingsRev += 1;          // triggers the ListView value cells to re-read
    }

    // value shown on the right of each row
    function valueText(k) {
        if (isFx(k)) return root[k] ? "ON" : "OFF";
        switch (k) {
        case "lrpm":   return String(root.launchRpm);
        case "theme":  return root.theme === 1 ? "LIGHT" : (root.theme === 2 ? "SUNSET" : (root.theme === 3 ? "CITY MAP" : "DARK"));
        case "nfont":  return root.neonFont ? "ON" : "OFF";
        case "ltint":  return root.logoTint === 1 ? "THEME" : root.logoTint === 2 ? "ACCENT" : "OFF";
        case "bgr":    return String(root.bgRed);
        case "bgg":    return String(root.bgGreen);
        case "bgb":    return String(root.bgBlue);
        case "rwing":  return (root.rightWing === 0 && root.speedunits === 0) ? "0-100 TIMER" : root.rightWingNames[root.rightWing];
        case "shift":  return String(root.rpmredline);
        case "limit":  return String(root.rpmmax);
        case "rdamp":  return String(root.rpmDamp);
        case "bcol":   return root.barColours === 1 ? "ZONES" : root.barColours === 2 ? "BLEND" : "ACCENT";
        case "gfrom":  return String(root.greenFrom);
        case "yfrom":  return String(root.yellowFrom);
        case "rfrom":  return String(root.redFrom);
        case "red":    return String(root.red);
        case "green":  return String(root.green);
        case "blue":   return String(root.blue);
        case "speed":  return root.speedunits === 0 ? "KM/H" : "MPH";
        case "dist":   return root.distunits  === 0 ? "KM" : "MI";
        case "chi":    return (root.tempunits === 1 ? Math.round(root.coolantHigh * 9/5 + 32) : Math.round(root.coolantHigh)) + "\u00B0";
        case "clo":    return (root.tempunits === 1 ? Math.round(root.coolantLow  * 9/5 + 32) : Math.round(root.coolantLow))  + "\u00B0";
        case "cun":    return root.tempunits === 0 ? "\u00B0C" : root.tempunits === 1 ? "\u00B0F" : "OFF";
        case "fhi":    return root.fuelHigh + "%";
        case "flo":    return root.fuelLow  + "%";
        case "fdmp":   return String(root.fuelDamp);
        case "othi":   return (root.oilTempUnits === 1 ? Math.round(root.oilTempHigh * 9/5 + 32) : Math.round(root.oilTempHigh)) + "\u00B0";
        case "otlo":   return (root.oilTempUnits === 1 ? Math.round(root.oilTempLow  * 9/5 + 32) : Math.round(root.oilTempLow))  + "\u00B0";
        case "otun":   return root.oilTempUnits === 0 ? "\u00B0C" : root.oilTempUnits === 1 ? "\u00B0F" : "OFF";
        case "pkon":   return root.showPeakGauge ? "TRUE" : "FALSE";
        case "pkpos":  return root.peakGaugePosition === 1 ? "1 TL" : root.peakGaugePosition === 2 ? "2 TR" : root.peakGaugePosition === 3 ? "3 BL" : "4 BR";
        case "pkrpm":  return root.peakShowRpm      ? "TRUE" : "FALSE";
        case "pkspd":  return root.peakShowSpeed    ? "TRUE" : "FALSE";
        case "pkafr":  return root.peakShowAfr      ? "TRUE" : "FALSE";
        case "pkotm":  return root.peakShowOilTemp  ? "TRUE" : "FALSE";
        case "pkopr":  return root.peakShowOilPress ? "TRUE" : "FALSE";
        case "pkcol":  return root.peakShowCoolant  ? "TRUE" : "FALSE";
        case "pkrst":  return "PUSH \u25B2";
        case "ophi":   return root.oilPressUnits === 1 ? (root.oilPressHigh / 14.5038).toFixed(1) : String(Math.round(root.oilPressHigh));
        case "oplo":   return root.oilPressUnits === 1 ? (root.oilPressLow  / 14.5038).toFixed(1) : String(Math.round(root.oilPressLow));
        case "opun":   return root.oilPressUnits === 0 ? "PSI" : root.oilPressUnits === 1 ? "BAR" : "OFF";
        case "bhi":    return root.batteryHigh.toFixed(1) + "V";
        case "blo":    return root.batteryLow.toFixed(1) + "V";
        case "ahi":    return root.afrSource === 0 ? (root.afrHigh * 14.7).toFixed(1) : root.afrHigh.toFixed(2) + "\u03BB";
        case "alo":    return root.afrSource === 0 ? (root.afrLow  * 14.7).toFixed(1) : root.afrLow.toFixed(2)  + "\u03BB";
        case "asrc":   return root.afrSource === 0 ? "AFR" : root.afrSource === 1 ? "LAMBDA" : "OFF";
        case "night":  return root.nightlight === 0 ? "OFF" : String(root.nightlight);
        case "swap":   return root.placementSwap ? "TRUE" : "FALSE";
        case "htn":    return root.hideTachNums  ? "TRUE" : "FALSE";
        case "hsl":    return root.hideShiftLights ? "TRUE" : "FALSE";
        case "mbtn":   return root.showModeButtons ? "TRUE" : "FALSE";
        case "vshift": return (root.vShift > 0 ? "+" : "") + root.vShift + " px";
        case "exit":   return "SAVE";
        }
        return "";
    }

    function openMenu()  { menuOpen = true; sel = 0; upArmed = false; downArmed = false; upHold = 0; downHold = 0; try { if (root.d) root.d.settings_on_offdata = 1; } catch (e) {} }
    function closeMenu() { menuOpen = false; try { if (root.d) root.d.settings_on_offdata = 0; } catch (e) {} }
    function moveSel(dir){
        var n = items.length;
        do { sel = ((sel + dir) % n + n) % n; } while (rowHidden(items[sel].k));
    }

    // ---- input handling (signal-driven edge detection) ---------------------
    function evalEdges() {
        var u = dUp(), dn = dDown(), l = dLeft(), r = dRight();
        if (!menuOpen) {
            if (u && !pUp) openMenu();
        } else {
            if (l && !pLeft)  moveSel(-1);
            if (r && !pRight) moveSel(1);
            if (u && !pUp)   { applyValue(1);  upHold = 0; }
            if (dn && !pDown){ applyValue(-1); downHold = 0; }
        }
        pUp = u; pDown = dn; pLeft = l; pRight = r;
        // mirror the flasher/bulb state (poll-driven; works without change signals)
        root.tLeftActive  = ((root.inputs & 0x40) !== 0);
        root.tRightActive = ((root.inputs & 0x80) !== 0);
    }
    Connections {
        target: root.d
        ignoreUnknownSignals: true
        function onInputsdataChanged()     { root.evalEdges(); }
        function onUdp_packetdataChanged() { root.evalEdges(); }
    }
    // Some backends update inputsdata without emitting a change signal, so the
    // Connections above may never fire on the hardware. Poll as a fallback —
    // evalEdges() is edge-triggered (via pUp/pDown/...), so this is harmless.
    Timer {
        interval: 30; running: true; repeat: true
        onTriggered: root.evalEdges()
    }
    Timer {   // hold-to-ramp for numeric rows (only runs while the menu is open)
        interval: 90; running: root.menuOpen; repeat: true
        onTriggered: {
            if (root.menuOpen && root.isRampable(root.items[root.sel].k)) {
                // upArmed/downArmed gate the ramp until the button is released
                // once, so the same Up-press that opened the menu can't ramp.
                if (root.dUp()) {
                    if (root.upArmed) { root.upHold += 1;
                        var ru = Math.max(1, 3 - Math.floor((root.upHold - 2) / 5));
                        if (root.upHold > 2 && root.upHold % ru === 0) root.applyValue(1);
                    }
                } else { root.upArmed = true; root.upHold = 0; }
                if (root.dDown()) {
                    if (root.downArmed) { root.downHold += 1;
                        var rd = Math.max(1, 3 - Math.floor((root.downHold - 2) / 5));
                        if (root.downHold > 2 && root.downHold % rd === 0) root.applyValue(-1);
                    }
                } else { root.downArmed = true; root.downHold = 0; }
            }
            // menu repaints only on navigation (openMenu/moveSel/applyValue),
            // so there is no per-pulse repaint here — keeps the IC7 responsive.
        }
    }

    // ---- settings overlay: panel + ListView -------------------------------
    //  Item-based, not a Canvas: only the rows that change repaint, the view
    //  recycles off-screen rows, and Rectangle.radius gives reliable rounded
    //  corners (no arcTo). Driven entirely by the D-pad: currentIndex follows
    //  root.sel; value cells re-read valueText() when settingsRev bumps.
    Item {
        id: menu
        anchors.fill: parent
        visible: root.menuOpen

        readonly property int visibleRows: 11
        readonly property int rowH: 30

        Rectangle { anchors.fill: parent; color: root.bgS(0.042, 1); opacity: 0.80 }   // dim the full-size dash behind

        Rectangle {
            id: panel
            width: 772; height: 452; anchors.centerIn: parent
            radius: 16; color: root.bgS(0.15, 6); border.color: root.bgS(0.508, 29); border.width: 2

            Text {
                text: "SETTINGS"; color: root.fg
                font.pixelSize: 24; font.bold: root.dispBold; font.family: root.dispFont
                anchors.horizontalCenter: parent.horizontalCenter; y: 12
            }
            Rectangle { x: 24; y: 46; width: parent.width - 48; height: 3; color: root.accentInk }

            // ----- LEFT: settings list -----
            ListView {
                id: menuList
                x: 22; y: 60
                width: 356; height: menu.visibleRows * menu.rowH
                clip: true
                interactive: false
                model: root.items
                currentIndex: root.sel
                highlightMoveDuration: 0
                highlightRangeMode: ListView.ApplyRange
                preferredHighlightBegin: 5 * menu.rowH
                preferredHighlightEnd:   6 * menu.rowH
                delegate: Item {
                    id: row
                    width: ListView.view.width
                    height: root.rowHidden(modelData.k) ? 0 : menu.rowH
                    visible: !root.rowHidden(modelData.k)
                    property bool current: ListView.isCurrentItem
                    Rectangle { visible: row.current; x: 0; y: 3; width: parent.width - 30; height: menu.rowH - 6; radius: 7; color: root.accent; opacity: 0.26 }
                    Rectangle { visible: row.current; x: 0; y: 3; width: 4; height: menu.rowH - 6; color: root.accentInk }
                    Text {
                        text: modelData.label
                        x: 20; anchors.verticalCenter: parent.verticalCenter
                        color: row.current ? root.fg : root.fgDim
                        font.pixelSize: 17; font.bold: true; font.family: root.menuFont
                    }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: 30
                        anchors.verticalCenter: parent.verticalCenter
                        text: { var r = root.settingsRev; return root.valueText(modelData.k); }
                        color: row.current ? root.fg : root.accentInk
                        font.pixelSize: 17; font.bold: true; font.family: root.menuFont
                    }
                }
            }
            Rectangle {   // scrollbar
                visible: menuList.contentHeight > menuList.height
                x: 384; y: 60; width: 4; height: menu.visibleRows * menu.rowH
                radius: 2; color: root.bgS(0.183, 18)
                Rectangle { x: 0; width: 4; radius: 2; color: root.accentInk
                    y: parent.height * menuList.visibleArea.yPosition
                    height: Math.max(24, parent.height * menuList.visibleArea.heightRatio) }
            }

            // ----- RIGHT: live preview of the running dash + per-row help -----
            Text { x: 404; y: 55; text: "LIVE PREVIEW"; color: root.fgDim
                   font.pixelSize: 13; font.bold: true; font.family: root.menuFont }
            Rectangle {
                x: 404; y: 74; width: 344; height: 206
                color: root.bgS(0.058, 2); border.color: root.bgS(0.508, 29); border.width: 1; radius: 6; clip: true
                ShaderEffectSource {
                    anchors.fill: parent; anchors.margins: 1
                    sourceItem: dashView
                    live: root.menuOpen
                    hideSource: false
                }
            }
            Text {   // per-row help
                x: 404; y: 294; width: 344; wrapMode: Text.WordWrap
                text: root.helpText(root.items[root.sel].k)
                color: root.fg2; font.pixelSize: 15; font.family: root.menuFont
            }

            Text {
                text: "Default units:  km \u00B7 \u00B0C \u00B7 bar \u00B7 \u03BB"
                color: root.fgDim; font.pixelSize: 12; font.family: root.menuFont
                x: 24; y: parent.height - 46
            }
            Text {
                text: "L / R  SELECT      U / D  CHANGE      EXIT + U  SAVE"
                color: root.fgDim; font.pixelSize: 13; font.family: root.menuFont
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height - 26
            }
        }
    }

    // ---- rev-lag debug readout (OFF by default). Flip showRawRpm to true to
    //      compare the raw rpm (from rpmtest) against the smoothed value on the
    //      needle while tuning a dash: if "raw" tracks the rev but "disp" trails,
    //      the lag is the spring (tune RPM DAMPING); if "raw" itself trails, the
    //      lag is upstream in the rpmdata feed. Sits below the cowl line (y:54).
    Rectangle {
        visible: root.showRawRpm
        x: 4; y: 54; width: dbgText.implicitWidth + 8; height: dbgText.implicitHeight + 4
        color: "#000000"; opacity: 0.55; radius: 4
    }
    Text {
        id: dbgText
        visible: root.showRawRpm
        x: 8; y: 56
        color: "#ffd23a"
        font.pixelSize: 14; font.bold: true
        font.family: uiFontR.status === FontLoader.Ready ? uiFontR.name : "sans-serif"
        text: "raw " + Math.round(root.rpm)
              + "   disp " + Math.round(root.rpmDisplay)
              + "   \u0394 " + Math.round(root.rpm - root.rpmDisplay)
    }

    // ---- raw-sensor readout (OFF by default). Flip showRawSensors to true to
    //      see the RAW values the host sends, to check unit/scale assumptions
    //      (e.g. is oilpressuredata really PSI?). Stacks under the rev-lag line.
    Rectangle {
        visible: root.showRawSensors
        x: 4; y: 76; width: rawSensText.implicitWidth + 8; height: rawSensText.implicitHeight + 4
        color: "#000000"; opacity: 0.55; radius: 4
    }
    Text {
        id: rawSensText
        visible: root.showRawSensors
        x: 8; y: 78
        color: "#7ee787"
        font.pixelSize: 13; font.bold: true
        font.family: uiFontR.status === FontLoader.Ready ? uiFontR.name : "sans-serif"
        text: "oilP=" + (root.d ? root.d.oilpressuredata : "?")
              + "  oilT=" + (root.d ? root.d.oiltempdata : "?")
              + "  cool=" + (root.d ? root.d.watertempdata : "?")
              + "  o2=" + (root.d ? root.d.o2data : "?")
              + "  spd=" + (root.d ? root.d.speeddata : "?")
    }
}
