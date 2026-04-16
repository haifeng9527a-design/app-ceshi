package scheduler

import (
	"context"
	"log"
	"time"

	"github.com/robfig/cron/v3"

	"tongxin-go/internal/service"
)

// ThresholdScanner Sprint 2：代理自定义阈值告警扫描器。
//
// 每 10 分钟扫一次全部 enabled 阈值，命中且未在 24h 防抖窗口内则
// notification.Create（走 DB + WS 完整路径）。
//
// 独立于 daily_commission 的 Scheduler：
//   - daily 受 REFERRAL_ENABLED 开关控制
//   - threshold scanner 常开（只要 ThresholdService 非 nil）
//
// 设计：
//   - 使用 ctx 超时 2 分钟，避免卡死 goroutine
//   - 任意一条 threshold 错不 abort 整个 batch（ScanAndFire 已聚合 errors）
type ThresholdScanner struct {
	svc  *service.ThresholdService
	cron *cron.Cron
}

func NewThresholdScanner(svc *service.ThresholdService) *ThresholdScanner {
	return &ThresholdScanner{svc: svc}
}

// Start 注册并启动 cron。幂等：再次调用不会重复注册。
func (s *ThresholdScanner) Start() {
	if s.cron != nil {
		return
	}
	if s.svc == nil {
		log.Println("[threshold-scanner] service nil, skip registration")
		return
	}
	s.cron = cron.New(cron.WithLocation(time.UTC))
	// 每 10 分钟扫描一次
	if _, err := s.cron.AddFunc("*/10 * * * *", s.scan); err != nil {
		log.Printf("[threshold-scanner] failed to register: %v", err)
		return
	}
	s.cron.Start()
	log.Println("[OK] Threshold scanner registered (every 10m)")
}

// Stop 优雅停止：最多等 30s 让当前 scan 完成。
func (s *ThresholdScanner) Stop() {
	if s.cron == nil {
		return
	}
	ctx := s.cron.Stop()
	select {
	case <-ctx.Done():
		log.Println("[threshold-scanner] stopped")
	case <-time.After(30 * time.Second):
		log.Println("[threshold-scanner] stop timed out after 30s")
	}
}

func (s *ThresholdScanner) scan() {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	scanned, fired, errs := s.svc.ScanAndFire(ctx)
	if len(errs) == 0 {
		if fired > 0 {
			log.Printf("[threshold-scanner] scanned=%d fired=%d", scanned, fired)
		}
		return
	}
	// 有错误：打印概要 + 前 3 条明细
	log.Printf("[threshold-scanner] scanned=%d fired=%d errors=%d", scanned, fired, len(errs))
	for i, e := range errs {
		if i >= 3 {
			log.Printf("[threshold-scanner] ... %d more errors omitted", len(errs)-3)
			break
		}
		log.Printf("[threshold-scanner]   err #%d: %v", i+1, e)
	}
}
