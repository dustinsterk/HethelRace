# HethelRace

A Lotus-inspired race dash for the GARW IC7 (800x480, Qt 5.12), built on the GTDash template.

- Arched, wedge-shaped rev bar (green -> Lotus yellow -> red) with a white leading edge, a fading tail when revs drop, and a tell-tale marker that holds the peak of each rev
- Rev bar colors are adjustable in settings: ZONES (GREEN / YELLOW / RED FROM rpm), BLEND or ACCENT
- Race animations, each with an FX: on/off row in settings: sequential LED shift lights, edge shift strobe, gear roll, redline bloom, limiter stutter, launch band (LAUNCH RPM), accel/brake bar, speed streaks, new-best flash, RACE-mode takeover, critical warning banner, cold-oil rev ceiling, shutdown sweep
- FX demo: selecting an FX row that is ON in the settings menu plays that effect in the live frame with simulated inputs
- Large center gear in a chamfered shield; pops on each gear change and pulses red at the shift point
- Speed under the gear, live RPM on the left (RPM/SPEED SWAP flips them)
- RIGHT WING slot, selectable in settings: 0-100 km/h (0-60 mph) timer, fuel %, max speed, max RPM, session timer, peak g, LOGO (shows `assets/wing_logo.png`, or any `assets/wing_logo_NAME.png` picked with the Logo file setting — replace the placeholder with your own image, a PNG with a transparent background; LOGO TINT recolors single-color artwork to the theme text color or the accent), or off
- Oil pressure, oil temp, AFR/lambda and coolant side gauges; optional PEAK card in any corner
- Battery, fuel, telltales, ECU text line, ODO/TRIP, optional RACE/SPORT buttons
- Two-level settings menu (Up opens it): groups on the left, that group's options beside them, with the live dash shrunk into a frame on the right and help for the selected row under it. The menu components (`SettingsMenu.qml`, `SettingBox.qml`, `Theme.qml`, `MonoText.qml`) and the moving grid behind the menu (`GridBackground.qml`, MENU GRID setting) are adapted from the AgeSolo dash by Tristan Beaulieu, MIT license (see `LICENSE-AgeSolo-menu.txt`). Accent defaults to Lotus yellow 255/224/0; background tint (BG RED/GREEN/BLUE) defaults to Lotus green 0/120/74; THEME switches DARK / LIGHT (set BG to 255/255/255 in LIGHT for a white dash) / SUNSET (fixed neon-dusk palette with a striped sun, palms, five-star shift lights and a red/blue shift strobe) / CITY MAP (the same palette on a night street-map backdrop with card-style panels). The two neon themes use the bundled Pricedown font (`assets/pricedown.ttf`, (c) Typodermic Fonts Inc.) for the gear, numbers and labels; NEON FONT turns it off

Install: copy the `HethelRace` folder to `/opt/IC7/library/` and reboot. Settings are stored as JSON in
`screen_configs/hethelrace_config.json`; an older `hethelrace_config.txt` is imported once.
