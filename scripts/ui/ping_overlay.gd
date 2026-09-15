extends CanvasLayer

@onready var ping_label: Label = $MarginContainer/PingLabel

# Color thresholds:
# Low Ping (< 80ms): Green
# Medium Ping (80 - 150ms): Orange
# High Ping (> 150ms): Red
const COLOR_LOW_PING: Color = Color(0.2, 0.9, 0.3, 1.0)
const COLOR_MED_PING: Color = Color(1.0, 0.65, 0.1, 1.0)
const COLOR_HIGH_PING: Color = Color(0.95, 0.25, 0.25, 1.0)

const UPDATE_INTERVAL: float = 0.3
var _time_since_update: float = 0.0

func _ready() -> void:
	# Ensure bold font and black outline
	var bold_font := SystemFont.new()
	bold_font.font_weight = 700
	ping_label.add_theme_font_override("font", bold_font)
	ping_label.add_theme_font_size_override("font_size", 20)
	ping_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
	ping_label.add_theme_constant_override("outline_size", 6)

	_update_ping()

func _process(delta: float) -> void:
	_time_since_update += delta
	if _time_since_update >= UPDATE_INTERVAL:
		_time_since_update = 0.0
		_update_ping()

func _update_ping() -> void:
	var ping_val: int = _get_current_ping()
	ping_label.text = "Ping: %d ms" % ping_val

	if ping_val < 80:
		ping_label.add_theme_color_override("font_color", COLOR_LOW_PING)
	elif ping_val <= 150:
		ping_label.add_theme_color_override("font_color", COLOR_MED_PING)
	else:
		ping_label.add_theme_color_override("font_color", COLOR_HIGH_PING)

func _get_current_ping() -> int:
	var base_rtt: float = 0.0
	if multiplayer != null and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		var enet_peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		if not multiplayer.is_server():
			# Remote client checking round-trip time to host/server (peer ID 1)
			var server_peer: ENetPacketPeer = enet_peer.get_peer(1)
			if server_peer:
				base_rtt = server_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
		else:
			# Host has 0 ms base network latency to itself
			base_rtt = 0.0

	var total_ping: int = int(base_rtt + Network.simulated_latency_ms)
	return maxi(0, total_ping)
