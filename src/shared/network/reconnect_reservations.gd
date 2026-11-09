class_name ReconnectReservations
extends RefCounted

## Reconnect bookkeeping for the dedicated server: the private token issued to
## each admitted human, the seats held for pilots who dropped mid-match, and
## stale peers whose departure was already handled when a rejoin displaced
## them. The match coordinator owns each held seat's deadline; a reservation
## only stays valid while its coordinator is current and still holds the seat.

# Admitted human peer id -> token that lets the player reclaim their seat.
var _tokens: Dictionary = {}
# Token -> {"peer_id", "player", "coordinator"} for held match seats.
var _reservations: Dictionary = {}
# Stale peers whose socket closing later must not run departure again.
var _replaced_peers: Dictionary = {}


func issue_token(peer_id: int) -> String:
	var token := Crypto.new().generate_random_bytes(NetworkProtocol.RECONNECT_TOKEN_BYTES).hex_encode()
	_tokens[peer_id] = token
	return token


## Forgets a departing peer's token and returns it ("" if it had none).
func take_token(peer_id: int) -> String:
	var token := String(_tokens.get(peer_id, ""))
	_tokens.erase(peer_id)
	return token


## The live peer still holding this token, or 0. A rejoin can arrive before
## the server notices the old connection dropped.
func peer_holding_token(token: String) -> int:
	if token.is_empty():
		return 0
	var peer_value: Variant = _tokens.find_key(token)
	return int(peer_value) if peer_value != null else 0


func has_reservation(token: String) -> bool:
	return _reservations.has(token)


func hold(token: String, peer_id: int, player: PlayerMatchState, coordinator: RefCounted) -> void:
	_reservations[token] = {"peer_id": peer_id, "player": player, "coordinator": coordinator}


## Puts back a reservation taken for an admission that then failed.
func restore(token: String, reservation: Dictionary) -> void:
	_reservations[token] = reservation


## Removes and returns the reservation for a token, or {} when the token is
## unknown, or its seat belongs to a match that has since ended or released it.
func take(token: String, coordinator: AuthoritativeMatchCoordinator) -> Dictionary:
	if token.is_empty() or not _reservations.has(token):
		return {}
	var reservation := _reservations[token] as Dictionary
	_reservations.erase(token)
	if not _is_live(reservation, coordinator):
		return {}
	return reservation


## Drops reservations whose seats the current coordinator no longer holds.
## Returns true when any were dropped.
func expire(coordinator: AuthoritativeMatchCoordinator) -> bool:
	var dropped := false
	for token in _reservations.keys():
		if not _is_live(_reservations[token] as Dictionary, coordinator):
			_reservations.erase(token)
			dropped = true
	return dropped


func is_empty() -> bool:
	return _reservations.is_empty()


func held_seat_count(coordinator: RefCounted) -> int:
	var count := 0
	for reservation: Dictionary in _reservations.values():
		if reservation.coordinator == coordinator:
			count += 1
	return count


## Display names the lobby must keep free for returning pilots.
func reserved_names() -> PackedStringArray:
	var names := PackedStringArray()
	for reservation: Dictionary in _reservations.values():
		names.append((reservation.player as PlayerMatchState).display_name)
	return names


func mark_replaced(peer_id: int) -> void:
	_replaced_peers[peer_id] = true


## True (once) when this peer's departure was already handled by a rejoin.
func consume_replaced(peer_id: int) -> bool:
	return _replaced_peers.erase(peer_id)


func clear() -> void:
	_tokens.clear()
	_reservations.clear()
	_replaced_peers.clear()


static func _is_live(reservation: Dictionary, coordinator: AuthoritativeMatchCoordinator) -> bool:
	return coordinator != null and reservation.coordinator == coordinator and coordinator.can_reconnect(int(reservation.peer_id))
