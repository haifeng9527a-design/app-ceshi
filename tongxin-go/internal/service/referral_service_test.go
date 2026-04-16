package service

import (
	"math"
	"testing"

	"tongxin-go/internal/model"
	"tongxin-go/internal/repository"
)

// 覆盖 PRD §5.2 的所有代数分支，不碰 DB。

func node(uid string, rate float64, isAgent, frozen bool) repository.UserRebateInfo {
	return repository.UserRebateInfo{
		UID:              uid,
		MyRebateRate:     rate,
		IsAgent:          isAgent,
		IsFrozenReferral: frozen,
	}
}

func findEvent(evs []repository.InsertableEvent, inviter, kind string) *repository.InsertableEvent {
	for i := range evs {
		if evs[i].InviterUID == inviter && evs[i].Kind == kind {
			return &evs[i]
		}
	}
	return nil
}

func approxEq(a, b float64) bool {
	return math.Abs(a-b) < 1e-6
}

// 场景 1（PRD §5.2 例 1 三层级差）：
//   admin → A(80%) → B(60%) → C(15%) → U
//   U 交易 fee=$100
//   期待：C=$15, B=$45, A=$20，合计 $80
func TestCascade_ThreeLayerLevelDiff(t *testing.T) {
	chain := []repository.UserRebateInfo{
		node("C", 0.15, false, false), // 直接 inviter（普通用户）
		node("B", 0.60, true, false),
		node("A", 0.80, true, false),
	}
	evs := ComputeCascadeEvents("U", chain, 100, model.ProductTypeFuturesClose, nil, 10)
	if len(evs) != 3 {
		t.Fatalf("expected 3 events, got %d", len(evs))
	}
	if e := findEvent(evs, "C", model.CommissionKindDirect); e == nil || !approxEq(e.CommissionAmount, 15) {
		t.Errorf("direct C=$15, got %+v", e)
	}
	if e := findEvent(evs, "B", model.CommissionKindOverride); e == nil || !approxEq(e.CommissionAmount, 45) {
		t.Errorf("override B=$45, got %+v", e)
	}
	if e := findEvent(evs, "A", model.CommissionKindOverride); e == nil || !approxEq(e.CommissionAmount, 20) {
		t.Errorf("override A=$20, got %+v", e)
	}
}

// 场景 2（PRD §5.2 例 2 平级）：
//   A(80%) → B(80%) → U，fee=$100
//   期待：B=$80 direct；A 级差 0，不写事件
func TestCascade_Equal(t *testing.T) {
	chain := []repository.UserRebateInfo{
		node("B", 0.80, true, false),
		node("A", 0.80, true, false),
	}
	evs := ComputeCascadeEvents("U", chain, 100, model.ProductTypeSpot, nil, 10)
	if len(evs) != 1 {
		t.Fatalf("expected 1 event, got %d", len(evs))
	}
	if e := findEvent(evs, "B", model.CommissionKindDirect); e == nil || !approxEq(e.CommissionAmount, 80) {
		t.Errorf("direct B=$80, got %+v", e)
	}
	if findEvent(evs, "A", model.CommissionKindOverride) != nil {
		t.Errorf("A should have no override event")
	}
}

// 场景 3（PRD §5.2 例 3 负级差）：
//   admin 降 A 到 40%（但 B 仍 60%）→ A 级差 = max(0, 40-60) = 0
//   B(60%) → A(40%) + C(30%)→U
//   期待：C=$30 direct, B=$30 override, A 不写
func TestCascade_NegativeDelta(t *testing.T) {
	chain := []repository.UserRebateInfo{
		node("C", 0.30, false, false),
		node("B", 0.60, true, false),
		node("A", 0.40, true, false), // 低于 B
	}
	evs := ComputeCascadeEvents("U", chain, 100, model.ProductTypeFuturesOpen, nil, 10)
	if len(evs) != 2 {
		t.Fatalf("expected 2 events, got %d", len(evs))
	}
	if e := findEvent(evs, "C", model.CommissionKindDirect); e == nil || !approxEq(e.CommissionAmount, 30) {
		t.Errorf("direct C=$30, got %+v", e)
	}
	if e := findEvent(evs, "B", model.CommissionKindOverride); e == nil || !approxEq(e.CommissionAmount, 30) {
		t.Errorf("override B=$30, got %+v", e)
	}
	if findEvent(evs, "A", model.CommissionKindOverride) != nil {
		t.Errorf("A should be skipped (delta <= 0)")
	}
}

// 场景 4：chain 中上级不是 agent → 链断
//   X(非 agent, 25%) → A(agent 30%) → U ；X 不是 agent 不能拿级差
//   但 chain 从直接 inviter 开始遍历，A 是直接 inviter → direct 30；
//   往上 X 不是 agent → 截断
func TestCascade_NonAgentBreaksChain(t *testing.T) {
	chain := []repository.UserRebateInfo{
		node("A", 0.30, true, false),  // 直接 inviter，是 agent
		node("X", 0.25, false, false), // 不是 agent 了
	}
	evs := ComputeCascadeEvents("U", chain, 100, model.ProductTypeSpot, nil, 10)
	if len(evs) != 1 {
		t.Fatalf("expected only direct, got %d", len(evs))
	}
	if e := findEvent(evs, "A", model.CommissionKindDirect); e == nil || !approxEq(e.CommissionAmount, 30) {
		t.Errorf("direct A=$30, got %+v", e)
	}
}

// 场景 5：直接 inviter 冻结 → direct event status=skipped_risk，但写入审计
func TestCascade_DirectFrozen(t *testing.T) {
	chain := []repository.UserRebateInfo{
		node("F", 0.20, false, true), // frozen
	}
	evs := ComputeCascadeEvents("U", chain, 100, model.ProductTypeCopyOpen, nil, 10)
	if len(evs) != 1 {
		t.Fatalf("expected 1 event, got %d", len(evs))
	}
	if evs[0].Status != model.CommissionEventStatusSkippedRisk {
		t.Errorf("expected skipped_risk, got %s", evs[0].Status)
	}
	if !approxEq(evs[0].CommissionAmount, 20) {
		t.Errorf("amount still computed (for audit), got %.8f", evs[0].CommissionAmount)
	}
}

// 场景 6：级联深度截断
//   构造 15 层，期待只发到 10 层 override（+1 direct = 11 事件）
func TestCascade_MaxDepth(t *testing.T) {
	chain := make([]repository.UserRebateInfo, 15)
	for i := 0; i < 15; i++ {
		// 递增 rate，每层产生正 delta
		chain[i] = node(
			string(rune('A'+i)),
			0.05+0.02*float64(i), // 0.05, 0.07, ..., 0.33
			true,                 // 都是 agent
			false,
		)
	}
	chain[0].IsAgent = false // 直接 inviter 是普通用户
	evs := ComputeCascadeEvents("U", chain, 100, model.ProductTypeFuturesClose, nil, 10)
	// 1 direct + 10 override = 11 条
	if len(evs) != 11 {
		t.Fatalf("expected 11 events (1 direct + 10 overrides), got %d", len(evs))
	}
}

// 场景 7：空 chain → 空 events
func TestCascade_Empty(t *testing.T) {
	if evs := ComputeCascadeEvents("U", nil, 100, model.ProductTypeSpot, nil, 10); len(evs) != 0 {
		t.Errorf("expected 0 events for empty chain, got %d", len(evs))
	}
}

// 场景 8：fee <= 0 → 空 events
func TestCascade_ZeroFee(t *testing.T) {
	chain := []repository.UserRebateInfo{node("A", 0.30, true, false)}
	if evs := ComputeCascadeEvents("U", chain, 0, model.ProductTypeSpot, nil, 10); len(evs) != 0 {
		t.Errorf("expected 0 events for zero fee, got %d", len(evs))
	}
}

// 场景 9：单调递增检查
//   A(80%) → B(60%) → C(70%) → U
//   cursor_child_rate 单调递增，C 用 70%，B 看到 cursor=70% delta=60-70<0 跳过，
//   A 看到 cursor=70% delta=80-70=10% → $10
func TestCascade_MonotonicCursor(t *testing.T) {
	chain := []repository.UserRebateInfo{
		node("C", 0.70, true, false),
		node("B", 0.60, true, false),
		node("A", 0.80, true, false),
	}
	evs := ComputeCascadeEvents("U", chain, 100, model.ProductTypeFuturesOpen, nil, 10)
	// direct: C $70; B skip; A override $10
	if len(evs) != 2 {
		t.Fatalf("expected 2 events, got %d", len(evs))
	}
	if e := findEvent(evs, "A", model.CommissionKindOverride); e == nil || !approxEq(e.CommissionAmount, 10) {
		t.Errorf("A override should be $10, got %+v", e)
	}
	if findEvent(evs, "B", model.CommissionKindOverride) != nil {
		t.Errorf("B should be skipped (70 - 70 = 0)")
	}
}
