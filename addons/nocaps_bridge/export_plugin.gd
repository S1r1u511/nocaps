@tool
extends EditorPlugin

var _export_plugin: AndroidExportPlugin


func _enter_tree() -> void:
	_export_plugin = AndroidExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null


class AndroidExportPlugin extends EditorExportPlugin:
	func _get_name() -> String:
		return "NocapsBridge"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		if debug:
			return PackedStringArray(["nocaps_bridge/bin/debug/plugin-debug.aar"])
		return PackedStringArray(["nocaps_bridge/bin/release/plugin-release.aar"])

	## The bridge .aar is shipped as a raw file, so Gradle cannot read its
	## transitive dependencies. Declare them here so they reach the APK's
	## classpath. Keep in sync with
	## platform/android/bridge_spike/plugin/build.gradle.kts.
	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray([
			"com.solanamobile:mobile-wallet-adapter-clientlib-ktx:2.0.7",
		])
