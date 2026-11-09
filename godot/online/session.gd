## Two trusted friends, locally simulated craft, host-authorized session membership.
## No object deserialization or client-selected identity in the data protocol.
extends Node

signal status_changed
signal joined
signal roster_changed

const PoseBuffer := preload("res://online/pose_buffer.gd")
const PROTOCOL := 1
const PORT := 27840
const TRACKS := ["network", "gp", "eridanus", "range", "circuit", "gp_dunes", "gp_glacier", "gp_basalt", "gp_mesa"]
const TIMEOUT_MS := 10000
var active := false
var connecting := false
var pilot := "Pilot"
var status := "Offline"
var world := {"track": "network"}
var players := {}
var buffers := {}
var last_received := {}
var pending := {}
var connect_started := 0
var sequence := 0.0
var epoch := 0.0
var fingerprint := ""
var use_vr := false

func _ready() -> void:
	# A plain text build manifest survives GDScript bytecode conversion in exports.
	fingerprint = FileAccess.get_file_as_string("res://online/build_id.txt").strip_edges()
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(func(): leave_game("Could not connect. Check the host address, UDP port and firewall."))
	multiplayer.server_disconnected.connect(func(): leave_game("Host disconnected. Return to the lobby to reconnect."))
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	if "--online-game-test" in OS.get_cmdline_user_args():
		get_tree().root.add_child.call_deferred(load("res://tests/test_online_game.gd").new())

static func clean_name(value: String) -> String:
	var result := ""
	for c in value.strip_edges():
		if c.unicode_at(0) >= 32 and c not in ["[", "]", "\\", "\n", "\r", "\t"]:
			result += c
		if result.length() == 20:
			break
	return result if not result.is_empty() else "Pilot"

func _status(message: String) -> void:
	status = message
	status_changed.emit()

func host_game(player_name: String, track: String, port := PORT) -> Error:
	leave_game()
	if track not in TRACKS or port < 1024 or port > 65535:
		_status("Choose a valid track and port (1024–65535).")
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 1, 3)
	if err != OK:
		_status("Cannot host on UDP %d. Another session may be using that port." % port)
		return err
	multiplayer.multiplayer_peer = peer
	pilot = clean_name(player_name)
	world = {"track": track}
	players = {1: pilot}
	active = true
	_status("HOSTING · UDP %d · waiting for your friend" % port)
	roster_changed.emit()
	return OK

func join_game(address: String, player_name: String, port := PORT) -> Error:
	leave_game()
	if address.strip_edges().is_empty() or address.length() > 253 or port < 1024 or port > 65535:
		_status("Enter the host's address and a port from 1024–65535.")
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address.strip_edges(), port, 3)
	if err != OK:
		_status("Could not start the connection. Check the address.")
		return err
	pilot = clean_name(player_name)
	multiplayer.multiplayer_peer = peer
	connecting = true
	connect_started = Time.get_ticks_msec()
	_status("Connecting to %s:%d…" % [address.strip_edges(), port])
	return OK

func leave_game(message := "Offline") -> void:
	active = false
	connecting = false
	players.clear()
	buffers.clear()
	pending.clear()
	last_received.clear()
	sequence = 0.0
	epoch = 0.0
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_status(message)
	roster_changed.emit()

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if connecting and now - connect_started > TIMEOUT_MS:
		leave_game("Connection timed out. Check the host address, Tailscale or UDP forwarding.")
	if active and multiplayer.is_server():
		for id in pending.keys():
			if now - int(pending[id]) > TIMEOUT_MS:
				multiplayer.multiplayer_peer.disconnect_peer(id)
				pending.erase(id)

func _connected() -> void:
	_hello.rpc_id(1, PROTOCOL, fingerprint, pilot)

func _peer_connected(id: int) -> void:
	if active and multiplayer.is_server():
		pending[id] = Time.get_ticks_msec()

func _peer_disconnected(id: int) -> void:
	pending.erase(id)
	players.erase(id)
	buffers.erase(id)
	last_received.erase(id)
	if active and multiplayer.is_server():
		_status("HOSTING · your friend left · ready for another connection")
	roster_changed.emit()

@rpc("any_peer", "call_remote", "reliable", 0)
func _hello(version: int, build: String, player_name: String) -> void:
	if not active or not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not pending.has(id):
		return
	if version != PROTOCOL or build != fingerprint:
		_rejected.rpc_id(id, "Different game version. Both players must download the same release.")
		return
	pending.erase(id)
	players[id] = clean_name(player_name)
	_welcome.rpc_id(id, PROTOCOL, fingerprint, world, players)
	_status("ONLINE · %s joined" % players[id])
	roster_changed.emit()

@rpc("authority", "call_remote", "reliable", 0)
func _welcome(version: int, build: String, options: Dictionary, roster: Dictionary) -> void:
	if not connecting:
		return
	if version != PROTOCOL or build != fingerprint or options.get("track", "") not in TRACKS or roster.size() != 2:
		leave_game("The host sent an incompatible session. Use the same game release.")
		return
	world = {"track": String(options.track)}
	players.clear()
	for id in roster:
		if not id is int or not roster[id] is String:
			leave_game("Invalid host roster.")
			return
		players[id] = clean_name(roster[id])
	connecting = false
	active = true
	_status("ONLINE · connected to %s" % players.get(1, "host"))
	roster_changed.emit()
	joined.emit()

@rpc("authority", "call_remote", "reliable", 0)
func _rejected(reason: String) -> void:
	leave_game(reason.left(160))

func publish_pose(pose: PackedFloat64Array) -> void:
	if not active or not PoseBuffer.valid_packet(pose):
		return
	if multiplayer.is_server():
		for id in players:
			if id != 1:
				_host_pose.rpc_id(id, pose)
	else:
		_client_pose.rpc_id(1, pose)

func _store(id: int, pose: PackedFloat64Array) -> void:
	if not players.has(id) or not PoseBuffer.valid_packet(pose):
		return
	var now := Time.get_ticks_msec()
	if now - int(last_received.get(id, -1000)) < 15:
		return
	if not buffers.has(id):
		buffers[id] = PoseBuffer.new()
	if buffers[id].push(pose, now):
		last_received[id] = now

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _client_pose(pose: PackedFloat64Array) -> void:
	if active and multiplayer.is_server():
		_store(multiplayer.get_remote_sender_id(), pose)

@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _host_pose(pose: PackedFloat64Array) -> void:
	if active and not multiplayer.is_server():
		_store(1, pose)

func pose_for(id: int) -> PackedFloat64Array:
	return buffers[id].sample(Time.get_ticks_msec()) if buffers.has(id) else PackedFloat64Array()
