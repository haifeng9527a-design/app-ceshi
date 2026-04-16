package scheduler

import (
	"log"
	"sync/atomic"
)

// Metrics holds referral-system operational metrics.
// These are simple atomic counters exposed via log statements for now;
// they can be wired to Prometheus registries when the metrics stack is added.
type Metrics struct {
	DailySettleTotal   atomic.Int64
	DailySettleErrors  atomic.Int64
	DailyCapHitTotal   atomic.Int64
	EventsPendingTotal atomic.Int64
	CascadeDepthSum    atomic.Int64
	CascadeDepthCount  atomic.Int64
}

// ReferralMetrics is the global metrics instance.
var ReferralMetrics = &Metrics{}

// LogSummary prints a summary of current metrics.
func (m *Metrics) LogSummary() {
	log.Printf("[referral-metrics] settle_total=%d settle_errors=%d cap_hits=%d avg_cascade_depth=%.1f",
		m.DailySettleTotal.Load(),
		m.DailySettleErrors.Load(),
		m.DailyCapHitTotal.Load(),
		func() float64 {
			c := m.CascadeDepthCount.Load()
			if c == 0 {
				return 0
			}
			return float64(m.CascadeDepthSum.Load()) / float64(c)
		}(),
	)
}

// RecordCascadeDepth records the depth of a cascade computation.
func (m *Metrics) RecordCascadeDepth(depth int) {
	m.CascadeDepthSum.Add(int64(depth))
	m.CascadeDepthCount.Add(1)
}

// RecordSettle records a successful daily settlement.
func (m *Metrics) RecordSettle() {
	m.DailySettleTotal.Add(1)
}

// RecordSettleError records a failed daily settlement.
func (m *Metrics) RecordSettleError() {
	m.DailySettleErrors.Add(1)
}

// RecordCapHit records when a daily cap was triggered.
func (m *Metrics) RecordCapHit() {
	m.DailyCapHitTotal.Add(1)
}
