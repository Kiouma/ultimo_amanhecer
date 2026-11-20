"""Gera data/passives/passive_tree.json (árvore passiva, GDD 4.2).

Uso: py tools/gen_passive_tree.py

O conteúdo (nomes e efeitos) fica nas tabelas abaixo; o layout (posições e ligações)
é calculado aqui. Rodar de novo sobrescreve o JSON. Os ids são estáveis enquanto a
estrutura (número de ramos, clusters e nós) não mudar: personagens salvos guardam ids.

Layout (coordenadas em "unidades de árvore", y para baixo):
- Centro: o nó notável "Último Amanhecer", ligado às 4 classes por raios de 3 nós.
- Anel interno (raio 260): as 4 classes iniciais (Guerreiro à esquerda, Pugilista em
  cima, Mago à direita, Arqueiro embaixo) e 5 nós entre cada par.
- Setor de classe: 3 ramos (-22°, 0°, +22°). Cada ramo: 3 nós de caminho, cluster
  (6 pequenos em anel + notável no meio), 2 de caminho, cluster, 2 de caminho e o fim
  (pedra angular no ramo do meio, notável nos laterais).
- Setor híbrido (entre duas classes, a 45°): sai do nó do meio do arco do anel; 3 de
  caminho, cluster, 2, cluster, 1 e uma pedra angular. Pontes de 1 nó ligam o híbrido
  aos ramos laterais das duas classes vizinhas.
"""
import json
import math
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "data", "passives", "passive_tree.json")

# Ângulo (graus, y para baixo) de cada classe.
CLASSES = {"warrior": 180, "brawler": 270, "mage": 0, "archer": 90}
# Híbridos: (classe A, classe B) -> id do setor.
HYBRIDS = [("brawler", "mage", "monk"), ("mage", "archer", "spellbow"), ("archer", "warrior", "hunter"), ("warrior", "brawler", "barbarian")]

R_START = 260.0
STEP = 55.0
RING = 60.0

# --- Conteúdo ----------------------------------------------------------------------

def e(**kw):
    return {k.replace("__", "."): v for k, v in kw.items()}

# Nós pequenos dos caminhos, por setor (ciclados).
PATH_SMALLS = {
    "warrior": [("Força", e(melee__damage=0.04)), ("Vigor", e(max_health_add=8)), ("Couraça", e(damage_taken=-0.015)), ("Fôlego", e(max_stamina_add=6)), ("Golpe econômico", e(melee__stamina_cost=-0.04)), ("Sangue forte", e(life_regen_add=0.15))],
    "archer": [("Precisão", e(ranged__damage=0.04)), ("Mão ágil", e(ranged__draw_time=-0.03)), ("Passo leve", e(move_speed=0.015)), ("Reflexos", e(attack_speed=0.02)), ("Arremesso", e(thrown__damage=0.05))],
    "mage": [("Intelecto", e(magic__damage=0.04)), ("Reserva arcana", e(max_mana_add=8)), ("Fluxo de mana", e(mana_regen=0.06)), ("Foco", e(magic__mana=-0.03)), ("Ressonância", e(aura_effect=0.02))],
    "brawler": [("Punho", e(unarmed__damage=0.05)), ("Resiliência", e(max_health_add=6)), ("Ritmo", e(attack_speed=0.02)), ("Ímpeto", e(unarmed__stamina_cost=-0.04)), ("Recuperação", e(stamina_regen=0.06)), ("Fôlego vital", e(life_regen_add=0.15))],
    "monk": [("Disciplina", e(unarmed__damage=0.03, magic__damage=0.02)), ("Meditação", e(mana_regen=0.04, stamina_regen=0.04)), ("Espírito", e(aura_effect=0.02))],
    "spellbow": [("Flecha arcana", e(ranged__damage=0.025, magic__damage=0.025)), ("Recarga", e(magic__cooldown=-0.03)), ("Vento", e(move_speed=0.012))],
    "hunter": [("Caça", e(ranged__damage=0.025, melee__damage=0.025)), ("Rastreio", e(noise=-0.03)), ("Emboscada", e(sneak_damage=0.06))],
    "barbarian": [("Brutalidade", e(melee__damage=0.025, unarmed__damage=0.03)), ("Couro grosso", e(max_health_add=7)), ("Teimosia", e(damage_taken=-0.012))],
    "center": [("Sobrevivência", e(gather_yield=0.04)), ("Vitalidade", e(max_health_add=5)), ("Remendo", e(heal=0.05)), ("Carga", e(carry_weight_add=3)), ("Artesão", e(craft_time=-0.04)), ("Regeneração", e(life_regen_add=0.1))],
}

# Notáveis dos setores de classe: 6 de cluster (2 por ramo, na ordem ramo esquerdo,
# meio, direito) + 2 de fim dos ramos laterais. Cada um: (nome, efeitos, pequeno do anel).
NOTABLES = {
    "warrior": [
        ("Braço de Ferro", e(melee__damage=0.15, melee__stamina_cost=-0.1), ("Força", e(melee__damage=0.03))),
        ("Muralha Viva", e(damage_taken=-0.06, max_health_add=25), ("Vigor", e(max_health_add=6))),
        ("Golpe Carregado", e(melee__channel=0.3, melee__damage=0.08), ("Concentração", e(melee__channel=0.05))),
        ("Lâmina Veloz", e(melee__attack_time=-0.1, attack_speed=0.04), ("Agilidade", e(attack_speed=0.015))),
        ("Fôlego de Batalha", e(max_stamina_add=25, stamina_regen=0.15), ("Fôlego", e(max_stamina_add=5))),
        ("Sangue Quente", e(life_regen_add=1.0, max_health_add=15), ("Sangue", e(life_regen_add=0.15))),
        ("Senhor da Guerra", e(melee__damage=0.12, max_health_add=20, damage_taken=-0.03), None),
        ("Inabalável", e(damage_taken=-0.08, max_stamina_add=15), None),
    ],
    "archer": [
        ("Olho de Águia", e(ranged__damage=0.15, headshot_damage=0.2), ("Precisão", e(ranged__damage=0.03))),
        ("Corda Tensa", e(ranged__draw_time=-0.12, ranged__arrow_speed=0.15), ("Mão ágil", e(ranged__draw_time=-0.025))),
        ("Aljava Infinita", e(ranged__recover_chance=0.3, ranged__damage=0.06), ("Recolher", e(ranged__recover_chance=0.05))),
        ("Pés Ligeiros", e(move_speed=0.05, sprint_stamina=-0.1), ("Passo leve", e(move_speed=0.012))),
        ("Lâminas Arremessadas", e(thrown__damage=0.2, thrown__attack_time=-0.08), ("Arremesso", e(thrown__damage=0.04))),
        ("Sombra", e(noise=-0.12, sneak_damage=0.25), ("Silêncio", e(noise=-0.03))),
        ("Mestre Atirador", e(ranged__damage=0.12, attack_speed=0.05, headshot_damage=0.15), None),
        ("Vento Cortante", e(ranged__arrow_speed=0.2, move_speed=0.03, ranged__draw_time=-0.06), None),
    ],
    "mage": [
        ("Chama Interior", e(magic__damage=0.15, magic__channel=0.15), ("Intelecto", e(magic__damage=0.03))),
        ("Poço de Mana", e(max_mana_add=30, mana_regen=0.15), ("Reserva arcana", e(max_mana_add=6))),
        ("Coração das Auras", e(aura_effect=0.12, reservation_efficiency=0.06), ("Ressonância", e(aura_effect=0.02))),
        ("Mente Clara", e(magic__cooldown=-0.1, magic__cast_time=-0.1), ("Clareza", e(magic__cooldown=-0.025))),
        ("Economia Arcana", e(magic__mana=-0.12), ("Foco", e(magic__mana=-0.025))),
        ("Escudo Místico", e(spell_resist=0.08, max_mana_add=15), ("Proteção", e(spell_resist=0.015))),
        ("Arquimago", e(magic__damage=0.14, max_mana_add=20, magic__cooldown=-0.05), None),
        ("Fonte Eterna", e(mana_regen=0.3, magic__mana=-0.06), None),
    ],
    "brawler": [
        ("Punhos de Pedra", e(unarmed__damage=0.2), ("Punho", e(unarmed__damage=0.04))),
        ("Sequência", e(attack_speed=0.06, unarmed__attack_time=-0.08), ("Ritmo", e(attack_speed=0.015))),
        ("Corpo Fechado", e(max_health_add=25, life_regen_add=0.6), ("Resiliência", e(max_health_add=5))),
        ("Esquiva", e(damage_taken=-0.05, move_speed=0.03), ("Ginga", e(move_speed=0.01))),
        ("Ímpeto Interior", e(unarmed__stamina_cost=-0.15, stamina_regen=0.12), ("Recuperação", e(stamina_regen=0.04))),
        ("Golpe Surpresa", e(sneak_damage=0.3, noise=-0.08), ("Espreita", e(sneak_damage=0.05))),
        ("Mestre de Mãos Vazias", e(unarmed__damage=0.18, attack_speed=0.04), None),
        ("Pele de Ferro", e(damage_taken=-0.07, max_health_add=15), None),
    ],
    "monk": [
        ("Harmonia Interior", e(unarmed__damage=0.1, magic__damage=0.1), ("Disciplina", e(unarmed__damage=0.03, magic__damage=0.02))),
        ("Mantra", e(aura_effect=0.1, mana_regen=0.1), ("Espírito", e(aura_effect=0.02))),
    ],
    "spellbow": [
        ("Flecha Encantada", e(ranged__damage=0.1, magic__damage=0.1), ("Flecha arcana", e(ranged__damage=0.025, magic__damage=0.025))),
        ("Tempo Dobrado", e(magic__cooldown=-0.08, ranged__draw_time=-0.08), ("Recarga", e(magic__cooldown=-0.03))),
    ],
    "hunter": [
        ("Caçador Nato", e(ranged__damage=0.1, melee__damage=0.1), ("Caça", e(ranged__damage=0.025, melee__damage=0.025))),
        ("Tocaia", e(sneak_damage=0.25, noise=-0.08), ("Emboscada", e(sneak_damage=0.06))),
    ],
    "barbarian": [
        ("Fúria Bárbara", e(melee__damage=0.1, unarmed__damage=0.12), ("Brutalidade", e(melee__damage=0.025, unarmed__damage=0.03))),
        ("Couro de Fera", e(max_health_add=25, damage_taken=-0.03), ("Couro grosso", e(max_health_add=7))),
    ],
}

# Pedras angulares: efeito forte com um custo.
KEYSTONES = {
    "warrior": ("Fúria Imprudente", e(melee__damage=0.4, damage_taken=0.15), "Muito mais dano corpo a corpo, mas recebe mais dano"),
    "archer": ("Tiro Certeiro", e(headshot_damage=1.0, ranged__draw_time=0.2), "Tiros na cabeça dobram de dano, mas o arco puxa mais devagar"),
    "mage": ("Pacto Arcano", e(magic__damage=0.35, max_mana_add=60, max_health_add=-40), "Troca vida por mana e poder mágico"),
    "brawler": ("Punho Ascético", e(unarmed__damage=0.6, melee__damage=-0.3, ranged__damage=-0.3), "Socos devastadores; armas rendem menos"),
    "monk": ("Voto de Silêncio", e(aura_effect=0.3, magic__mana=0.25), "Auras muito mais fortes; feitiços custam mais mana"),
    "spellbow": ("Sobrecarga Arcana", e(magic__damage=0.3, ranged__damage=0.15, magic__cooldown=0.2), "Mais dano mágico e à distância; feitiços recarregam devagar"),
    "hunter": ("Predador", e(sneak_damage=0.8, damage_taken=0.1), "Ataques surpresa enormes, mas fica mais frágil"),
    "barbarian": ("Sede de Sangue", e(life_regen_add=3.0, max_mana_add=-40), "Regenera vida rápido; perde mana máxima"),
}

CENTER_NOTABLE = ("Último Amanhecer", e(melee__damage=0.05, ranged__damage=0.05, magic__damage=0.05, unarmed__damage=0.05, thrown__damage=0.05, max_health_add=10))

CLASS_NAMES = {"warrior": "Guerreiro", "archer": "Arqueiro", "mage": "Mago", "brawler": "Pugilista"}

# --- Montagem ----------------------------------------------------------------------

nodes = {}
order = []


def pol(r, deg):
    a = math.radians(deg)
    return [round(r * math.cos(a), 1), round(r * math.sin(a), 1)]


def add(nid, name, kind, pos, effects, group, **extra):
    assert nid not in nodes, nid
    n = {"id": nid, "name": name, "kind": kind, "pos": pos, "links": [], "effects": effects, "group": group}
    n.update(extra)
    nodes[nid] = n
    order.append(nid)
    return nid


def link(a, b):
    if b not in nodes[a]["links"] and a not in nodes[b]["links"]:
        nodes[a]["links"].append(b)


class Cycler:
    def __init__(self, pool):
        self.pool = pool
        self.i = 0

    def next(self):
        item = self.pool[self.i % len(self.pool)]
        self.i += 1
        return item


def small(nid, cyc, pos, group):
    name, eff = cyc.next()
    return add(nid, name, "small", pos, eff, group)


def cluster(prefix, center_r, ang, notable, group):
    """Anel de 6 pequenos + notável no meio. Retorna (entrada, saída)."""
    name, eff, ring_small = notable
    cx, cy = pol(center_r, ang)
    radial = ang  # direção para fora
    ring = []
    for k, rel in enumerate([180, 120, 60, 0, -60, -120]):
        dx, dy = pol(RING, radial + rel)
        ring.append(add("%s_s%d" % (prefix, k), ring_small[0], "small", [round(cx + dx, 1), round(cy + dy, 1)], ring_small[1], group))
    for k in range(6):
        link(ring[k], ring[(k + 1) % 6])
    nid = add("%s_n" % prefix, name, "notable", [cx, cy], eff, group)
    link(ring[2], nid)
    link(ring[4], nid)
    return ring[0], ring[3]


def path(prefix, r0, count, ang, cyc, group, prev):
    r = r0
    for k in range(count):
        r += STEP
        nid = small("%s_%d" % (prefix, k), cyc, pol(r, ang), group)
        link(prev, nid)
        prev = nid
    return prev, r


# Centro.
center = add("center", CENTER_NOTABLE[0], "notable", [0.0, 0.0], CENTER_NOTABLE[1], "center")
center_cyc = Cycler(PATH_SMALLS["center"])

starts = {}
for cls, ang in CLASSES.items():
    starts[cls] = add("start_%s" % cls, CLASS_NAMES[cls], "start", pol(R_START, ang), {}, cls, **{"class": cls})
    prev = center
    for k in range(3):
        nid = small("spoke_%s_%d" % (cls, k), center_cyc, pol(65.0 * (k + 1), ang), "center")
        link(prev, nid)
        prev = nid
    link(prev, starts[cls])

# Anel interno: 5 nós entre classes vizinhas; o do meio é a raiz do híbrido.
hybrid_roots = {}
ring_next = {}  # (classe, "pos"/"neg") -> nó do anel colado ao ramo lateral daquele lado
for a, b, hid in HYBRIDS:
    a0 = CLASSES[a]
    a1 = CLASSES[b]
    if a1 < a0:
        a1 += 360
    prev = starts[a]
    for k in range(5):
        ang = a0 + (a1 - a0) * (k + 1) / 6.0
        nid = small("ring_%s_%d" % (hid, k), center_cyc, pol(R_START, ang), "center")
        link(prev, nid)
        prev = nid
        if k == 2:
            hybrid_roots[hid] = (nid, ang)
        if k == 0:
            ring_next[(a, "pos")] = nid
        if k == 4:
            ring_next[(b, "neg")] = nid
    link(prev, starts[b])

# Setores de classe.
side_anchor = {}  # (classe, lado) -> nó de caminho depois do 1º cluster (para pontes)
for cls, ang0 in CLASSES.items():
    cyc = Cycler(PATH_SMALLS[cls])
    notables = NOTABLES[cls]
    firsts = []
    for bi, off in enumerate([-22, 0, 22]):
        ang = ang0 + off
        pre = "%s_b%d" % (cls, bi)
        prev, r = path(pre + "_p0", R_START, 3, ang, cyc, cls, starts[cls])
        firsts.append(pre + "_p0_0")
        entry, exit_ = cluster(pre + "_c0", r + STEP + RING, ang, notables[bi * 2], cls)
        link(prev, entry)
        r += STEP + 2 * RING
        prev, r = path(pre + "_p1", r, 2, ang, cyc, cls, exit_)
        if off != 0:
            side_anchor[(cls, "neg" if off < 0 else "pos")] = (nodes[prev]["id"], ang)
        entry, exit_ = cluster(pre + "_c1", r + STEP + RING, ang, notables[bi * 2 + 1], cls)
        link(prev, entry)
        r += STEP + 2 * RING
        prev, r = path(pre + "_p2", r, 2, ang, cyc, cls, exit_)
        end_pos = pol(r + STEP * 1.2, ang)
        if off == 0:
            name, eff, desc = KEYSTONES[cls]
            end = add(pre + "_key", name, "keystone", end_pos, eff, cls, desc=desc)
        else:
            name, eff, _ = notables[6 if off < 0 else 7]
            end = add(pre + "_end", name, "notable", end_pos, eff, cls)
        link(prev, end)
    # Entradas por fora do início: o setor de uma classe também se alcança pelo anel
    # interno (o início de outra classe não pode ser alocado nem atravessado).
    link(firsts[0], ring_next[(cls, "neg")])
    link(firsts[2], ring_next[(cls, "pos")])
    link(firsts[1], firsts[0])
    link(firsts[1], firsts[2])

# Setores híbridos + pontes.
for a, b, hid in HYBRIDS:
    root, ang = hybrid_roots[hid]
    cyc = Cycler(PATH_SMALLS[hid])
    notables = NOTABLES[hid]
    prev, r = path(hid + "_p0", R_START, 3, ang, cyc, hid, root)
    entry, exit_ = cluster(hid + "_c0", r + STEP + RING, ang, notables[0], hid)
    link(prev, entry)
    r += STEP + 2 * RING
    prev, r = path(hid + "_p1", r, 2, ang, cyc, hid, exit_)
    # Pontes: do caminho do híbrido aos ramos laterais vizinhos (classe a: lado +, classe b: lado -).
    for side_cls, side in ((a, "pos"), (b, "neg")):
        other, other_ang = side_anchor[(side_cls, side)]
        oa = other_ang
        while oa - ang > 180:
            oa -= 360
        while ang - oa > 180:
            oa += 360
        mid_ang = (ang + oa) / 2.0
        bridge = small("%s_bridge_%s" % (hid, side_cls), cyc, pol(r + 8.0, mid_ang), hid)
        link(prev, bridge)
        link(bridge, other)
    entry, exit_ = cluster(hid + "_c1", r + STEP + RING, ang, notables[1], hid)
    link(prev, entry)
    r += STEP + 2 * RING
    prev, r = path(hid + "_p2", r, 1, ang, cyc, hid, exit_)
    name, eff, desc = KEYSTONES[hid]
    end = add(hid + "_key", name, "keystone", pol(r + STEP * 1.2, ang), eff, hid, desc=desc)
    link(prev, end)

# --- Saída -------------------------------------------------------------------------

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w", encoding="utf-8", newline="\n") as f:
    f.write("[\n")
    lines = [json.dumps(nodes[i], ensure_ascii=False, separators=(",", ":")) for i in order]
    f.write(",\n".join("  " + line for line in lines))
    f.write("\n]\n")

kinds = {}
for n in nodes.values():
    kinds[n["kind"]] = kinds.get(n["kind"], 0) + 1
print("%d nós: %s" % (len(nodes), kinds))
