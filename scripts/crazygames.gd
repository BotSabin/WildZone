extends RefCounted
## Thin bridge to the CrazyGames HTML5 SDK (v3). Does nothing outside the web build
## or when the SDK is not on the page, so the game also runs on itch.io / desktop.


static func _js(code: String) -> void:
	if not OS.has_feature("web"):
		return
	# window.cg() (defined in the export's head_include) queues the call until the SDK is ready.
	JavaScriptBridge.eval("try { if (window.cg) { window.cg(function () { %s }); } } catch (e) { console.log(e); }" % code, true)


static func loading_stop() -> void:
	_js("window.CrazyGames.SDK.game.loadingStop();")


static func gameplay_start() -> void:
	_js("window.CrazyGames.SDK.game.gameplayStart();")


static func gameplay_stop() -> void:
	_js("window.CrazyGames.SDK.game.gameplayStop();")


static func happy_time() -> void:
	_js("window.CrazyGames.SDK.game.happytime();")
