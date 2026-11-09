class_name LobbyCommandOutcome
extends RefCounted

## What a lobby or match command decided. LobbyMatchCommands returns one and
## NetworkBridge applies it in a single place, so the command service needs no
## reference to the bridge and can be tested with a bare ServerLobby.

## Non-empty when the request is refused; nothing else is applied.
var rejected_message: String = ""
## Publish the lobby state to every admitted peer.
var broadcast_lobby: bool = false
## NPC peers the lobby removed; their world entities must go too.
var removed_npc_ids: Array = []
## The lobby result whose `added_npcs` need world entities.
var added_npc_result: Dictionary = {}
## Start the match coordinator for this leader after publishing the lobby.
var start_match: bool = false
## Eject this peer: remove it from the world and disconnect it.
var eject_peer_id: int = 0
## Replace the finished match with a fresh rematch.
var fresh_rematch: bool = false
## Forward the coordinator's queued events to clients.
var drain_coordinator: bool = false
## After draining, drop a coordinator that finished and publish the lobby.
var release_finished_match: bool = false


static func rejected(message: String) -> LobbyCommandOutcome:
	var outcome := LobbyCommandOutcome.new()
	outcome.rejected_message = message
	return outcome


func is_rejected() -> bool:
	return not rejected_message.is_empty()
