class_name DraftOffer
extends RefCounted

var peer_id: int
var token: String
var card_ids: Array[StringName] = []
var selected_card_id: StringName
var locked: bool = false
var build_complete: bool = false
var skipped: bool = false


func _init(peer_id_value: int = 0, token_value: String = "") -> void:
	peer_id = peer_id_value
	token = token_value
