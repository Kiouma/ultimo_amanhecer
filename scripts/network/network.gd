extends Node
## Rede (autoload "Network"). Co-op de até 5 jogadores com servidor autoritativo (GDD 14):
## - o servidor (quem hospeda) manda nos zumbis, na vida de todos, no dano e nas mortes;
## - cada cliente controla só o movimento do próprio personagem (resposta imediata);
## - ataques: o cliente detecta o acerto e PEDE o dano ao servidor (Health.take_damage).
## Sem rede (modo solo) o jogo roda como servidor sem clientes, com o mesmo código.

signal hosted
signal joined
signal connection_failed(reason: String)
signal server_closed

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 5


## Verdadeiro quando há conexão de verdade (host ou cliente). Falso no modo solo.
func is_online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not peer is OfflineMultiplayerPeer \
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func host(port := DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		connection_failed.emit("Não foi possível abrir a porta %d (%s)." % [port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	hosted.emit()
	return OK


func join(address: String, port := DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		connection_failed.emit("Endereço inválido: %s (%s)." % [address, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _ready() -> void:
	multiplayer.connected_to_server.connect(joined.emit)
	multiplayer.connection_failed.connect(func() -> void:
		leave()
		connection_failed.emit("Não conectou. Confira o IP e se o host está esperando."))
	multiplayer.server_disconnected.connect(func() -> void:
		leave()
		server_closed.emit())


# --- Barulho (GDD 5.1) -------------------------------------------------------------
# A IA dos zumbis roda só no servidor, então o barulho feito num cliente vai para lá.

func emit_noise(position: Vector3, loudness: float, source: Node) -> void:
	if multiplayer.is_server():
		EventBus.noise_emitted.emit(position, loudness, source)
	elif is_online():
		_noise_on_server.rpc_id(1, position, loudness, source.get_path() if source else NodePath())


@rpc("any_peer", "call_remote", "unreliable")
func _noise_on_server(position: Vector3, loudness: float, source_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	EventBus.noise_emitted.emit(position, minf(loudness, 60.0), get_node_or_null(source_path))
