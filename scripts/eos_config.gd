extends Node

## EOS credentials loader.
##
## File priority:
##   1. res://eos_config.local.json  - dev-only override. DO NOT COMMIT (contains secrets).
##   2. user://eos_config.json       - per-user fallback; a template is written here on
##                                     first run if neither file exists.
##
## Optional fields:
##   display_name      Used for anonymous login and lobby display. Defaults to OS user name.
##   login.method      "persistent_auth" | "devtool" | "account_portal" | "anonymous" | "auto"
##   login.devtool_server_url       Default "localhost:4545"
##   login.devtool_credential_name  Name you set inside the Epic Dev Auth Tool.
##   login.fallback_to_account_portal  Try account portal if the configured method fails.
##   login.fallback_to_anonymous       Try anonymous login last (dev only).

const LOCAL_PATH := "res://eos_config.local.json"
const USER_PATH := "user://eos_config.json"

var credentials: HCredentials = null
var display_name := ""
var login_method := "auto"
var devtool_server_url := "localhost:4545"
var devtool_credential_name := ""
var fallback_to_account_portal := true
var fallback_to_anonymous := false

var loaded_from := ""


func _ready() -> void:
	_load()


func has_credentials() -> bool:
	return credentials != null and credentials.client_id != ""


func _load() -> void:
	var data: Dictionary = {}
	for path in [LOCAL_PATH, USER_PATH]:
		if FileAccess.file_exists(path):
			data = _read_json(path)
			loaded_from = path
			break

	if data.is_empty():
		var err := _write_template(USER_PATH)
		if err != OK:
			push_error("EOSConfig: could not write template to %s (err=%s)" % [USER_PATH, error_string(err)])
		else:
			push_warning("EOSConfig: no config found. Template written to %s - fill it in and restart." % USER_PATH)
		return

	credentials = HCredentials.new()
	credentials.product_name = String(data.get("product_name", "Chamber Draw"))
	credentials.product_version = String(data.get("product_version", "1.0.0"))
	credentials.product_id = String(data.get("product_id", ""))
	credentials.sandbox_id = String(data.get("sandbox_id", ""))
	credentials.deployment_id = String(data.get("deployment_id", ""))
	credentials.client_id = String(data.get("client_id", ""))
	credentials.client_secret = String(data.get("client_secret", ""))
	credentials.encryption_key = String(data.get("encryption_key", ""))

	display_name = String(data.get("display_name", OS.get_environment("USERNAME").strip_edges()))
	if display_name.is_empty():
		display_name = "Player"
	if display_name.length() > 64:
		display_name = display_name.substr(0, 64)

	if data.has("login") and typeof(data.login) == TYPE_DICTIONARY:
		var login: Dictionary = data.login
		login_method = String(login.get("method", login_method))
		devtool_server_url = String(login.get("devtool_server_url", devtool_server_url))
		devtool_credential_name = String(login.get("devtool_credential_name", devtool_credential_name))
		fallback_to_account_portal = bool(login.get("fallback_to_account_portal", fallback_to_account_portal))
		fallback_to_anonymous = bool(login.get("fallback_to_anonymous", fallback_to_anonymous))

	if not has_credentials():
		push_warning("EOSConfig: loaded from %s but client_id is empty - EOS login will fail." % loaded_from)
	else:
		print("EOSConfig: loaded credentials from %s (product=%s, sandbox=%s)" % [loaded_from, credentials.product_id, credentials.sandbox_id])


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("EOSConfig: invalid JSON in %s" % path)
		return {}
	return parsed


func _write_template(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string("""{
	"product_name": "Chamber Draw",
	"product_version": "1.0.0",
	"product_id": "PASTE_PRODUCT_ID_HERE",
	"sandbox_id": "PASTE_SANDBOX_ID_HERE",
	"deployment_id": "PASTE_DEPLOYMENT_ID_HERE",
	"client_id": "PASTE_CLIENT_ID_HERE",
	"client_secret": "PASTE_CLIENT_SECRET_HERE",
	"encryption_key": "PASTE_64_HEX_ENCRYPTION_KEY_HERE",
	"display_name": "PlayerName",
	"login": {
		"method": "auto",
		"devtool_server_url": "localhost:4545",
		"devtool_credential_name": "my-devauth-name",
		"fallback_to_account_portal": true,
		"fallback_to_anonymous": false
	}
}""")
	f.close()
	return OK
