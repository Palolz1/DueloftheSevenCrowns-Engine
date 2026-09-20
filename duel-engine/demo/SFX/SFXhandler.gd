#SFXhandler.gd
extends Node

var _streams: Dictionary = {}
var _player: AudioStreamPlayer

func _ready():
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_preload_sfx()

func _preload_sfx():
	var paths = {
		"check": "res://SFX/check.wav",
		"checkmate": "res://SFX/checkmate.wav",
		"newgame": "res://SFX/newgame.wav",
		"promotion": "res://SFX/promotion.wav"
	}
	
	for key in paths.keys():
		var stream = load(paths[key]) as AudioStream
		if stream:
			_streams[key] = stream
		else:
			push_warning("SFXHandler: Failed to load " + paths[key])

func play(sfx_name: String):
	if sfx_name in _streams:
		_player.stream = _streams[sfx_name]
		_player.play()
	else:
		push_warning("SFXHandler: Unknown SFX '" + sfx_name + "'")
