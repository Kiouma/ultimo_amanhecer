extends Node
## Rede (autoload "Network"). Co-op de até 5 jogadores com servidor autoritativo (GDD 14):
## - o servidor (quem hospeda) manda nos zumbis, na vida de todos, no dano e nas mortes;
## - cada cliente controla só o movimento do próprio personagem (resposta imediata);
## - ataques: o cliente detecta o acerto e PEDE o dano ao servidor (Health.take_damage).
## Sem rede (modo solo) o jogo roda como servidor sem clientes, com o mesmo código.
##
## Jogar pela internet (amigos em outras cidades):
## - Ao hospedar, tenta abrir a porta sozinho no roteador (UPnP) e descobre o IP público
##   para passar aos amigos (upnp_finished). Se a internet do host usa CGNAT (comum no
##   Brasil), abrir porta não adianta: o aviso sugere uma VPN de jogos (Radmin, ZeroTier,
##   Tailscale) ou IPv6.
## - Aperto de mão (autenticação do SceneMultiplayer): o cliente manda a versão do jogo
##   (VERSION + impressão digital dos dados); versão diferente é recusada com aviso, em
##   vez de entrar e quebrar no meio.
## - Pacotes comprimidos (menos upload para o host).

signal hosted
signal joined
signal connection_failed(reason: String)
signal server_closed
## Resultado da abertura da porta (UPnP): {ok, external_ip, cgnat, message}.
signal upnp_finished(info: Dictionary)

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 5
## Versão de rede: mude ao lançar uma versão que não conversa com a anterior.
const VERSION := "0.10"
const COMPRESSION := ENetConnection.COMPRESS_RANGE_CODER

## Passado escolhido no menu (versões antigas). O passado agora vem do personagem salvo.
var background := "survivor"
## Último resultado do UPnP ({} = ainda não tentou ou não é host).
var upnp_info := {}
## Porta em uso pelo host.
var port := DEFAULT_PORT

var _upnp: UPNP
var _upnp_thread: Thread
var _reject_reason := ""


## Verdadeiro quando há conexão de verdade (host ou cliente). Falso no modo solo.
func is_online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not peer is OfflineMultiplayerPeer \
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Versão completa (versão + impressão digital dos dados do jogo): host e amigos precisam
## estar com o mesmo jogo, senão itens/receitas diferentes quebram a partida.
func full_version() -> String:
	return "%s-%s" % [VERSION, _data_fingerprint()]


func host(at_port := DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(at_port, MAX_PLAYERS - 1)
	if err != OK:
		connection_failed.emit(tr("Não foi possível abrir a porta %d (%s).") % [at_port, error_string(err)])
		return err
	peer.host.compress(COMPRESSION)
	port = at_port
	_setup_auth()
	multiplayer.multiplayer_peer = peer
	hosted.emit()
	_open_port_async(at_port)
	return OK


## address: "IP", "IP:porta", "[IPv6]:porta" ou só o IPv6.
func join(address: String) -> Error:
	leave()
	var target := parse_address(address)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(target[0], target[1])
	if err != OK:
		connection_failed.emit(tr("Endereço inválido: %s (%s).") % [address, error_string(err)])
		return err
	peer.host.compress(COMPRESSION)
	_reject_reason = ""
	_setup_auth()
	multiplayer.multiplayer_peer = peer
	return OK


func leave() -> void:
	_close_port()
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


## ["host", porta] a partir do texto digitado.
static func parse_address(text: String) -> Array:
	var s := text.strip_edges()
	var p := DEFAULT_PORT
	if s.begins_with("["):  # [IPv6]:porta
		var close := s.find("]")
		if close > 0:
			var rest := s.substr(close + 1)
			if rest.begins_with(":") and rest.substr(1).is_valid_int():
				p = rest.substr(1).to_int()
			s = s.substr(1, close - 1)
	elif s.count(":") == 1:  # IPv4/nome:porta (IPv6 puro tem vários ":")
		var parts := s.split(":")
		if parts[1].is_valid_int():
			p = parts[1].to_int()
		s = parts[0]
	return [s if s != "" else "127.0.0.1", p]


## Tempo de ida e volta até o host (ms), ou -1 (solo/host).
func ping_ms() -> int:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null or multiplayer.is_server() or not is_online():
		return -1
	var server := peer.get_peer(1)
	return int(server.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if server else -1


func _ready() -> void:
	multiplayer.connected_to_server.connect(joined.emit)
	multiplayer.connection_failed.connect(func() -> void:
		var reason := _reject_reason if _reject_reason != "" else tr("Não conectou. Confira o IP e se o host está esperando.")
		leave()
		connection_failed.emit(reason))
	multiplayer.server_disconnected.connect(func() -> void:
		var reason := _reject_reason
		leave()
		if reason != "":
			connection_failed.emit(reason)
		else:
			server_closed.emit())


func _exit_tree() -> void:
	_close_port()


# --- Aperto de mão (versão) --------------------------------------------------------------

func _setup_auth() -> void:
	var sm := multiplayer as SceneMultiplayer
	if sm == null:
		return
	sm.auth_timeout = 8.0
	sm.auth_callback = _on_auth
	if not sm.peer_authenticating.is_connected(_on_peer_authenticating):
		sm.peer_authenticating.connect(_on_peer_authenticating)
		sm.peer_authentication_failed.connect(_on_peer_auth_failed)


## Começou a autenticar: o cliente se apresenta ao host com a versão.
func _on_peer_authenticating(id: int) -> void:
	if not multiplayer.is_server() and id == 1:
		(multiplayer as SceneMultiplayer).send_auth(1, ("HELLO:" + full_version()).to_utf8_buffer())


func _on_auth(id: int, data: PackedByteArray) -> void:
	var sm := multiplayer as SceneMultiplayer
	var text := data.get_string_from_utf8()
	if multiplayer.is_server():
		if text == "HELLO:" + full_version():
			sm.send_auth(id, "OK".to_utf8_buffer())
			sm.complete_auth(id)
		else:
			# Versão diferente: avisa qual é a do host e derruba logo depois.
			sm.send_auth(id, ("BAD:" + full_version()).to_utf8_buffer())
			get_tree().create_timer(1.0).timeout.connect(func() -> void:
				if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
					sm.disconnect_peer(id))
	elif id == 1:
		if text == "OK":
			sm.complete_auth(1)
		elif text.begins_with("BAD:"):
			_reject_reason = tr("Versão diferente da do host (sua: %s, host: %s). Usem o mesmo executável do jogo.") % [full_version(), text.substr(4)]


func _on_peer_auth_failed(id: int) -> void:
	if not multiplayer.is_server() and id == 1 and _reject_reason == "":
		_reject_reason = tr("O host não respondeu ao aperto de mão (versão antiga do jogo?).")


static var _fingerprint := ""


## Impressão digital curta dos arquivos de dados (itens, receitas, zumbis...).
static func _data_fingerprint() -> String:
	if _fingerprint != "":
		return _fingerprint
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	var files: Array[String] = []
	_collect_json("res://data", files)
	files.sort()
	for path in files:
		if path.contains("/i18n/"):
			continue  # traduções não mudam a partida
		ctx.update(path.to_utf8_buffer())
		ctx.update(FileAccess.get_file_as_bytes(path))
	_fingerprint = ctx.finish().hex_encode().left(6)
	return _fingerprint


static func _collect_json(dir: String, out: Array[String]) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_collect_json(dir.path_join(sub), out)
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() == "json":
			out.append(dir.path_join(f))


# --- Abrir a porta no roteador (UPnP) -----------------------------------------------------

func _open_port_async(at_port: int) -> void:
	upnp_info = {}
	if _upnp_thread and _upnp_thread.is_started():
		_upnp_thread.wait_to_finish()
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_work.bind(at_port))


## Roda numa thread (descobrir o roteador demora alguns segundos).
func _upnp_work(at_port: int) -> void:
	var info := {"ok": false, "external_ip": "", "cgnat": false, "message": ""}
	var upnp := UPNP.new()
	var err := upnp.discover(2000, 2)
	if err != UPNP.UPNP_RESULT_SUCCESS or upnp.get_gateway() == null or not upnp.get_gateway().is_valid_gateway():
		info.message = "no_router"
	else:
		info.external_ip = upnp.query_external_address()
		info.cgnat = _is_private_ip(info.external_ip)
		if "--no-upnp" in OS.get_cmdline_user_args():
			info.message = "skipped"  # testes: só consulta o roteador, não abre a porta
			_finish_upnp.call_deferred(info)
			return
		var map_err := upnp.add_port_mapping(at_port, at_port, "Ultimo Amanhecer", "UDP")
		info.ok = map_err == UPNP.UPNP_RESULT_SUCCESS
		info.message = "ok" if info.ok else "mapping_failed"
		if info.ok:
			_upnp = upnp
	_finish_upnp.call_deferred(info)


func _finish_upnp(info: Dictionary) -> void:
	if _upnp_thread and _upnp_thread.is_started():
		_upnp_thread.wait_to_finish()
	if not multiplayer.is_server() or not is_online():
		_close_port()
		return
	upnp_info = info
	upnp_finished.emit(info)


func _close_port() -> void:
	if _upnp:
		_upnp.delete_port_mapping(port, "UDP")
		_upnp = null


## IP do roteador que não é público (CGNAT 100.64/10 ou faixas privadas): amigos de fora
## não conseguem chegar nele, nem com a porta aberta.
static func _is_private_ip(ip: String) -> bool:
	var p := ip.split(".")
	if p.size() != 4:
		return ip == ""
	var a := p[0].to_int()
	var b := p[1].to_int()
	return a == 10 or a == 127 or (a == 100 and b >= 64 and b <= 127) or (a == 172 and b >= 16 and b <= 31) \
		or (a == 192 and b == 168) or a == 0


## Texto para o host sobre como os amigos entram (pausa e aviso ao hospedar).
func share_text() -> String:
	if upnp_info.is_empty():
		return tr("Abrindo a porta %d no roteador...") % port
	if upnp_info.get("ok", false) and not upnp_info.get("cgnat", false):
		return tr("Porta %d aberta. Seus amigos entram com: %s") % [port, "%s:%d" % [upnp_info.external_ip, port]]
	if upnp_info.get("cgnat", false):
		return tr("Sua internet usa CGNAT: amigos de fora não alcançam seu IP. Usem uma VPN de jogos (Radmin VPN, ZeroTier ou Tailscale) e entrem pelo IP dela.")
	return tr("Não deu para abrir a porta %d sozinho (UPnP desligado?). Abra a porta %d UDP no roteador ou usem uma VPN de jogos (Radmin VPN, ZeroTier ou Tailscale).") % [port, port]


## Endereço para copiar e mandar aos amigos ("" se ainda não há).
func share_address() -> String:
	if upnp_info.get("ok", false) and not upnp_info.get("cgnat", false):
		return "%s:%d" % [upnp_info.external_ip, port]
	return ""


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
