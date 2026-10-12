extends RefCounted
class_name Links

## Public links shown in the app. Keep in sync with nocaps-web `lib/config.ts`.
const DISCORD := "https://discord.gg/zHFjRHPYWG"
const PLATFORM := "https://play.nocaps.fun"

## Opens a link in the system browser (Android) or a new tab (web).
static func open(url: String) -> void:
	OS.shell_open(url)
