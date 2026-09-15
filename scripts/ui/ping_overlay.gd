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

	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		Network.send_ping_probe()
	_update_ping()

func _process(delta: float) -> void:
	_time_since_update += delta
	if _time_since_update >= UPDATE_INTERVAL:
		_time_since_update = 0.0
		if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
			Network.send_ping_probe()
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
	if multiplayer != null and multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			base_rtt = 0.0
		else:
			var enet_peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
			if enet_peer:
				var server_peer: ENetPacketPeer = enet_peer.get_peer(1)
				if server_peer:
					var rtt: float = server_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
					var last_rtt: float = server_peer.get_statistic(ENetPacketPeer.PEER_LAST_ROUND_TRIP_TIME)
					# Once ENet's RTT converges (below 350ms), use it so overlay matches /ping exactly
					if rtt < 350.0 and rtt > 0.0:
						base_rtt = rtt
					elif last_rtt < 350.0 and last_rtt > 0.0:
						base_rtt = last_rtt
					elif Network.current_real_ping > 0:
						# During the initial ~1s before ENet converges, use probe so 500ms default is avoided
						base_rtt = float(Network.current_real_ping)
			elif Network.current_real_ping > 0:
				base_rtt = float(Network.current_real_ping)

	var total_ping: int = int(base_rtt + Network.simulated_latency_ms)
	return maxi(0, total_ping)
