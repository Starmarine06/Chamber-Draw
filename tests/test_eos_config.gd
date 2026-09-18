@tool
extends McpTestSuite

## Tests the pure helper logic of EOSConfig (JSON parsing + template writing).
## Deliberately does NOT call _load(): it reads res://eos_config.local.json
## which contains production credentials. Instantiation off-tree skips _ready,
## so no config file is ever touched by these tests.

func suite_name() -> String:
	return "eos_config"


func _make_config() -> Variant:
	return load("res://scripts/eos_config.gd").new()


func test_has_credentials_false_without_load() -> void:
	var cfg: Variant = _make_config()
	assert_false(cfg.has_credentials(), "no credentials before a config is parsed")


func test_read_json_parses_dictionary() -> void:
	var path := "user://test_eos_config_read.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("""{"client_id":"test_id","login":{"method":"anonymous"}}""")
	f.close()
	var cfg: Variant = _make_config()
	var data: Dictionary = cfg._read_json(path)
	assert_eq(data.get("client_id", ""), "test_id", "nested login block parses too")
	assert_eq(typeof(data.get("login", null)), TYPE_DICTIONARY, "login kept as a dictionary")
	DirAccess.open("user://").remove("test_eos_config_read.json")


func test_read_json_invalid_returns_empty() -> void:
	var path := "user://test_eos_config_bad.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("this is not json {")
	f.close()
	var cfg: Variant = _make_config()
	assert_eq(cfg._read_json(path).size(), 0, "invalid JSON degrades to an empty dict")
	DirAccess.open("user://").remove("test_eos_config_bad.json")


func test_read_json_missing_file_returns_empty() -> void:
	var cfg: Variant = _make_config()
	assert_eq(cfg._read_json("user://test_eos_config_does_not_exist.json").size(), 0, "missing file degrades to empty dict")


func test_write_template_produces_parseable_placeholder_json() -> void:
	var path := "user://test_eos_config_template.json"
	var cfg: Variant = _make_config()
	var err: Error = cfg._write_template(path)
	assert_eq(err, OK, "template written without error")
	var data: Dictionary = cfg._read_json(path)
	assert_eq(data.get("client_id", ""), "PASTE_CLIENT_ID_HERE", "placeholder values present")
	assert_eq(data.get("product_name", ""), "Chamber Draw")
	var login: Dictionary = data.get("login", {})
	assert_eq(login.get("method", ""), "auto", "template defaults to auto login")
	DirAccess.open("user://").remove("test_eos_config_template.json")