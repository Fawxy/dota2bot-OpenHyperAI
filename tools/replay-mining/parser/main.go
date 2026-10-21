// Replay parser for lane-management mining. Usage: go run ./parser <replay.dem> > out/<id>.ndjson
//
// NOT COMPILED OR RUN as part of the repo checks: written against manta's documented API and never
// executed here. Run `go mod tidy` first and expect to fix class/property names against a real replay
// (use manta's dump tools). Assumptions:
//   - Game time is CDOTAGamerulesProxy "m_pGameRules.m_fGameTime" minus "m_pGameRules.m_flGameStartTime".
//   - Heroes are CDOTA_Unit_Hero_* entities; slots are assigned in entity creation order.
//     Position = cell coordinates * 128 + in-cell offset (see worldPos).
//   - Neutrals are CDOTA_BaseNPC_Creep_Neutral; lane creeps are CDOTA_BaseNPC_Creep_Lane.
//   - Camp boxes come from CDOTA_NeutralSpawner (m_vecMins / m_vecMaxs relative to origin) at game start.
//   - Combat log damage entries name attackers/targets by name string; entity indices are recovered
//     through a name->latest-entity map built from the entity stream.
//
// Events (NDJSON, one per line):
//   {"k":"pos","t","hero":slot,"team":2|3,"x","y"}            every 0.5 s per hero
//   {"k":"dmg","t","src":"hero:<slot>"|"lanecreep:<team>"|"neutral","dst":"neutral:<idx>","campHint":[x,y]}
//   {"k":"neutral","t","ent","x","y","alive"}                 every 1 s
//   srcEnt and creep samples are deliberately not emitted (see README): pull divert/half detection is unavailable.
//   {"k":"camp","x","y","type","hx","hy"}                    spawner boxes at game start
package main

import (
	"encoding/json"
	"fmt"
	"math"
	"os"
	"strings"

	"github.com/dotabuff/manta"
	"github.com/dotabuff/manta/dota"
)

var out = json.NewEncoder(os.Stdout)

type state struct {
	gameStart  float32
	lastHero   float64
	lastSecond float64
	campsDone  bool
	heroSlot   map[int32]int
	heroByName map[string]*manta.Entity
	byUnitName map[string]map[int32]*manta.Entity
}

func emit(v map[string]any) { _ = out.Encode(v) }

func worldPos(e *manta.Entity) (float64, float64) {
	cx, _ := e.GetUint64("CBodyComponent.m_cellX")
	cy, _ := e.GetUint64("CBodyComponent.m_cellY")
	ox, _ := e.GetFloat32("CBodyComponent.m_vecX")
	oy, _ := e.GetFloat32("CBodyComponent.m_vecY")
	return float64(cx)*128 - 16384 + float64(ox), float64(cy)*128 - 16384 + float64(oy)
}

func gameTime(p *manta.Parser, s *state) float64 {
	rules := p.FindEntity("CDOTAGamerulesProxy")
	if rules == nil {
		return math.NaN()
	}
	now, _ := rules.GetFloat32("m_pGameRules.m_fGameTime")
	start, _ := rules.GetFloat32("m_pGameRules.m_flGameStartTime")
	if start != 0 {
		s.gameStart = start
	}
	return float64(now - s.gameStart)
}

func (s *state) entitiesNamed(name string) []*manta.Entity {
	var list []*manta.Entity
	for _, e := range s.byUnitName[name] {
		list = append(list, e)
	}
	return list
}

func laneCreepTeam(name string) (int, bool) {
	switch {
	case strings.Contains(name, "creep_goodguys"):
		return 2, true
	case strings.Contains(name, "creep_badguys"):
		return 3, true
	}
	return 0, false
}

func nearest(cands, anchors []*manta.Entity) *manta.Entity {
	var best *manta.Entity
	bestD := math.Inf(1)
	for _, c := range cands {
		cx, cy := worldPos(c)
		for _, a := range anchors {
			ax, ay := worldPos(a)
			if d := math.Hypot(cx-ax, cy-ay); d < bestD {
				bestD, best = d, c
			}
		}
	}
	return best
}

func teamOf(e *manta.Entity) int {
	t, _ := e.GetInt32("m_iTeamNum")
	return int(t)
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: go run ./parser <replay.dem>")
		os.Exit(1)
	}
	f, err := os.Open(os.Args[1])
	if err != nil {
		panic(err)
	}
	defer f.Close()
	p, err := manta.NewStreamParser(f)
	if err != nil {
		panic(err)
	}
	s := &state{heroSlot: map[int32]int{}, heroByName: map[string]*manta.Entity{}, byUnitName: map[string]map[int32]*manta.Entity{}, lastHero: -1, lastSecond: -1}

	p.OnEntity(func(e *manta.Entity, op manta.EntityOp) error {
		name := e.GetClassName()
		if op&manta.EntityOpCreated != 0 && strings.HasPrefix(name, "CDOTA_Unit_Hero_") {
			if _, ok := s.heroSlot[e.GetIndex()]; !ok {
				s.heroSlot[e.GetIndex()] = len(s.heroSlot)
			}
		}
		if n, ok := e.GetString("m_iszUnitName"); ok {
			if op&manta.EntityOpDeleted != 0 {
				delete(s.byUnitName[n], e.GetIndex())
			} else {
				if s.byUnitName[n] == nil {
					s.byUnitName[n] = map[int32]*manta.Entity{}
				}
				s.byUnitName[n][e.GetIndex()] = e
			}
		}
		if strings.HasPrefix(name, "CDOTA_Unit_Hero_") {
			s.heroByName[name] = e
		}
		return nil
	})

	p.Callbacks.OnCNETMsg_Tick(func(*dota.CNETMsg_Tick) error {
		t := gameTime(p, s)
		if math.IsNaN(t) || t < 0 {
			return nil
		}
		if !s.campsDone {
			s.campsDone = true
			for _, e := range p.FilterEntity(func(e *manta.Entity) bool { return e.GetClassName() == "CDOTA_NeutralSpawner" }) {
				x, y := worldPos(e)
				minX, _ := e.GetFloat32("m_vecMins.x")
				maxX, _ := e.GetFloat32("m_vecMaxs.x")
				minY, _ := e.GetFloat32("m_vecMins.y")
				maxY, _ := e.GetFloat32("m_vecMaxs.y")
				typ, _ := e.GetString("m_iszNeutralType")
				emit(map[string]any{"k": "camp", "x": x, "y": y, "type": typ, "hx": float64(maxX-minX) / 2, "hy": float64(maxY-minY) / 2})
			}
		}
		if t-s.lastHero >= 0.5 {
			s.lastHero = t
			for idx, slot := range s.heroSlot {
				if e := p.FindEntityByIndex(idx); e != nil {
					x, y := worldPos(e)
					emit(map[string]any{"k": "pos", "t": t, "hero": slot, "team": teamOf(e), "x": x, "y": y})
				}
			}
		}
		if t-s.lastSecond >= 1 {
			s.lastSecond = t
			for _, e := range p.FilterEntity(func(e *manta.Entity) bool {
				return e.GetClassName() == "CDOTA_BaseNPC_Creep_Neutral"
			}) {
				x, y := worldPos(e)
				life, _ := e.GetInt32("m_lifeState")
				emit(map[string]any{"k": "neutral", "t": t, "ent": e.GetIndex(), "x": x, "y": y, "alive": life == 0})
			}
		}
		return nil
	})

	p.Callbacks.OnCMsgDOTACombatLogEntry(func(m *dota.CMsgDOTACombatLogEntry) error {
		if m.GetType() != dota.DOTA_COMBATLOG_TYPES_DOTA_COMBATLOG_DAMAGE {
			return nil
		}
		t := float64(m.GetTimestamp()) - float64(s.gameStart)
		attacker, _ := p.LookupStringByIndex("CombatLogNames", int32(m.GetAttackerName()))
		target, _ := p.LookupStringByIndex("CombatLogNames", int32(m.GetTargetName()))
		if !strings.Contains(target, "neutral") {
			return nil
		}
		neutrals := s.entitiesNamed(target)
		if len(neutrals) == 0 {
			return nil
		}
		// Combat-log names are shared by many entities, so entities are resolved by proximity:
		// a hero is unique by name and hits the nearest same-name neutral; lane-creep attackers
		// cannot be told apart, so only the team is emitted (no srcEnt) and the target is the
		// same-name neutral closest to any creep of that team.
		var dst *manta.Entity
		src := "neutral"
		if team, ok := laneCreepTeam(attacker); ok {
			src = fmt.Sprintf("lanecreep:%d", team)
			var creeps []*manta.Entity
			for _, e := range p.FilterEntity(func(e *manta.Entity) bool { return e.GetClassName() == "CDOTA_BaseNPC_Creep_Lane" }) {
				if teamOf(e) == team {
					creeps = append(creeps, e)
				}
			}
			dst = nearest(neutrals, creeps)
		} else if ae := s.heroByName[attacker]; ae != nil {
			if slot, ok := s.heroSlot[ae.GetIndex()]; ok {
				src = fmt.Sprintf("hero:%d", slot)
				dst = nearest(neutrals, []*manta.Entity{ae})
			}
		}
		if dst == nil {
			return nil
		}
		x, y := worldPos(dst)
		emit(map[string]any{"k": "dmg", "t": t, "src": src, "dst": fmt.Sprintf("neutral:%d", dst.GetIndex()), "campHint": []float64{x, y}})
		return nil
	})

	if err := p.Start(); err != nil {
		panic(err)
	}
}
