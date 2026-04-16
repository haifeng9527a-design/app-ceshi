package scheduler

import (
	"context"
	"log"
	"time"

	"github.com/robfig/cron/v3"

	"tongxin-go/internal/service"
)

// WeeklyReportScheduler Sprint 5：每周一 UTC 01:00（= 北京 09:00）生成上周的周报。
//
// 决策：独立于 daily_commission / threshold_scanner 的 Scheduler，便于单独关停。
// 单 agent 超时 90s（chromedp 冷启 ~3s，页面渲染 ~5s，截图 ~1s），上限留余量。
// 全量 agent 的 ctx 超时 30min，避免慢查询拖垮整个 cron runner。
type WeeklyReportScheduler struct {
	svc  *service.WeeklyReportService
	cron *cron.Cron
}

func NewWeeklyReportScheduler(svc *service.WeeklyReportService) *WeeklyReportScheduler {
	return &WeeklyReportScheduler{svc: svc}
}

// Start 注册 cron「0 1 * * 1」= 每周一 UTC 01:00。
// 幂等：重复调用不会重复注册。
func (s *WeeklyReportScheduler) Start() {
	if s.cron != nil {
		return
	}
	if s.svc == nil {
		log.Println("[weekly-report-scheduler] service nil, skip registration")
		return
	}
	s.cron = cron.New(cron.WithLocation(time.UTC))
	if _, err := s.cron.AddFunc("0 1 * * 1", s.run); err != nil {
		log.Printf("[weekly-report-scheduler] failed to register: %v", err)
		return
	}
	s.cron.Start()
	log.Println("[OK] Weekly report scheduler registered (Monday 01:00 UTC = Beijing 09:00)")
}

// Stop 优雅停止，最多等 5 分钟让当前 run 跑完（chromedp 截图需要时间）。
func (s *WeeklyReportScheduler) Stop() {
	if s.cron == nil {
		return
	}
	ctx := s.cron.Stop()
	select {
	case <-ctx.Done():
		log.Println("[weekly-report-scheduler] stopped")
	case <-time.After(5 * time.Minute):
		log.Println("[weekly-report-scheduler] stop timed out after 5m")
	}
}

func (s *WeeklyReportScheduler) run() {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Minute)
	defer cancel()

	// 生成「上周」——cron 在周一 01:00 UTC 触发时，now-7d 正好落在上周周一，
	// ComputeWeekRange 会把它归一到上周的 [周一 00:00, 本周周一 00:00)。
	weekRef := time.Now().AddDate(0, 0, -7)

	start := time.Now()
	ok, fail, errs := s.svc.GenerateAll(ctx, weekRef)
	log.Printf("[weekly-report-scheduler] done: ok=%d fail=%d duration=%s",
		ok, fail, time.Since(start).Round(time.Second))
	for i, e := range errs {
		log.Printf("[weekly-report-scheduler]   err #%d: %v", i+1, e)
	}
}
