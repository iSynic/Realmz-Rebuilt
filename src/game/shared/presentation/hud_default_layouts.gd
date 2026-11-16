## The HUD settings a new or reset profile starts with, in the saved-settings form
## `HudPreferences.from_data` reads: the Fixed HUD, with the project owner's own modular
## overworld and combat arrangements ready for when the modular HUD is switched on.
## Positions are fractions of the free space; scales are the per-panel size.
class_name HudDefaultLayouts
extends RefCounted

const OVERWORLD := {
	"compactCommands": false,
	"effectsBar": {"opacity": 0.85, "visible": false},
	"effectsPosition": {"x": 1.0, "y": 0.7605},
	"modular": false,
	"panels": [
		{"autoHide": true, "backgroundOpacity": 0.9, "customPosition": true, "revealOnChanges": true, "revealOnHover": true, "scale": 1.0, "x": 1.0, "y": 0.1481},
		{"autoHide": true, "backgroundOpacity": 0.9, "customPosition": true, "revealOnChanges": true, "revealOnHover": true, "scale": 1.0, "x": 0.5598, "y": 1.0},
		{"autoHide": true, "backgroundOpacity": 0.9, "customPosition": true, "revealOnChanges": false, "revealOnHover": true, "scale": 1.0, "x": 0.0, "y": 0.0},
		{"autoHide": true, "backgroundOpacity": 0.9, "customPosition": true, "revealOnChanges": false, "revealOnHover": true, "scale": 1.0, "x": 0.0824, "y": 0.0},
	],
	"statusStrip": {"opacity": 0.85, "visible": true},
	"statusStripPosition": {"x": 0.5199, "y": 0.0},
	"stripOrientations": ["vertical", "horizontal", "auto"],
}

const COMBAT := {
	"bucketCount": 4.0,
	"compactCommands": false,
	"effectsBar": {"opacity": 0.85, "visible": true},
	"extraOrientations": ["auto", "auto"],
	"extraPanels": [
		{"autoHide": false, "backgroundOpacity": 0.9, "customPosition": false, "revealOnChanges": false, "revealOnHover": true, "scale": 1.25, "x": 0.0, "y": 0.0},
		{"autoHide": false, "backgroundOpacity": 0.9, "customPosition": false, "revealOnChanges": false, "revealOnHover": true, "scale": 1.5, "x": 0.0, "y": 0.0},
	],
	"modular": false,
	"panels": [
		{"autoHide": true, "backgroundOpacity": 0.9, "customPosition": false, "revealOnChanges": true, "revealOnHover": true, "scale": 1.0, "x": 0.0, "y": 0.0},
		{"autoHide": false, "backgroundOpacity": 0.9, "customPosition": false, "revealOnChanges": true, "revealOnHover": true, "scale": 1.25, "x": 0.1663, "y": 0.1829},
		{"autoHide": false, "backgroundOpacity": 0.9, "customPosition": true, "revealOnChanges": false, "revealOnHover": true, "scale": 1.25, "x": 0.0, "y": 0.339},
		{"autoHide": false, "backgroundOpacity": 0.9, "customPosition": false, "revealOnChanges": false, "revealOnHover": true, "scale": 1.5, "x": 0.0, "y": 0.0},
	],
	"statusStrip": {"opacity": 0.85, "visible": true},
	"stripOrientations": ["vertical", "auto", "auto"],
}
