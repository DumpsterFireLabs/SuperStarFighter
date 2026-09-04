extends SceneTree


func _initialize() -> void:
	var output := "Godot Engine and bundled third-party component notices\n"
	output += "Generated from Engine APIs in Godot %s.\n" % Engine.get_version_info().string
	output += "Upstream: https://godotengine.org/license/\n\n"
	output += Engine.get_license_text() + "\n\n"
	for component in Engine.get_copyright_info():
		output += "COMPONENT: %s\n" % component.name
		for part in component.parts:
			output += "Files: %s\n" % ", ".join(part.files)
			output += "Copyright: %s\n" % "; ".join(part.copyright)
			output += "License: %s\n\n" % part.license
	var licenses := Engine.get_license_info()
	var names := licenses.keys()
	names.sort()
	for name in names:
		output += "LICENSE: %s\n%s\n\n" % [name, licenses[name]]
	var file := FileAccess.open("res://docs/GODOT_COPYRIGHT.txt", FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(output)
	file.close()
	print("SSF_ENGINE_NOTICES_OK components=%d licenses=%d" % [Engine.get_copyright_info().size(), names.size()])
	quit(0)
