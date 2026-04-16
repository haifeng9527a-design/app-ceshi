package scheduler

import (
	"context"
	"log"
	"time"

	"github.com/robfig/cron/v3"

	"tongxin-go/internal/config"
	"tongxin-go/internal/service"
)

// Scheduler wraps cron jobs that need the referral service.
type Scheduler struct {
	cfg         *config.Config
	referralSvc *service.ReferralService
	cron        *cron.Cron
}

// NewScheduler creates a new scheduler. Call Start() to register and begin jobs.
func NewScheduler(cfg *config.Config, referralSvc *service.ReferralService) *Scheduler {
	return &Scheduler{
		cfg:         cfg,
		referralSvc: referralSvc,
	}
}

// Start registers cron jobs and begins the scheduler.
// If REFERRAL_ENABLED is false, it logs a message and returns immediately.
func (s *Scheduler) Start() {
	if !s.cfg.ReferralEnabled {
		log.Println("[scheduler] referral disabled, daily commission job not registered")
		return
	}

	// Use UTC timezone for consistent daily settlement across deployments.
	s.cron = cron.New(cron.WithLocation(time.UTC))

	// Daily at UTC 00:00 — settle yesterday's commission events.
	_, err := s.cron.AddFunc("0 0 * * *", s.settleDailyCommission)
	if err != nil {
		log.Printf("[scheduler] failed to register daily commission job: %v", err)
		return
	}

	s.cron.Start()
	log.Println("[scheduler] daily commission job registered (UTC 00:00)")
}

// Stop gracefully shuts down the cron scheduler, waiting for running jobs.
func (s *Scheduler) Stop() {
	if s.cron != nil {
		ctx := s.cron.Stop()
		// Wait up to 30s for running job to finish
		select {
		case <-ctx.Done():
			log.Println("[scheduler] cron stopped gracefully")
		case <-time.After(30 * time.Second):
			log.Println("[scheduler] cron stop timed out after 30s")
		}
	}
}

func (s *Scheduler) settleDailyCommission() {
	// Settle yesterday (UTC). The cron fires at 00:00 UTC, so "yesterday"
	// is the full 24h window whose events we batch-settle.
	yesterday := time.Now().UTC().AddDate(0, 0, -1)
	log.Printf("[scheduler] starting daily commission settlement for %s", yesterday.Format("2006-01-02"))

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	if err := s.referralSvc.SettleDailyCommission(ctx, yesterday); err != nil {
		log.Printf("[scheduler] daily commission settlement failed: %v", err)
		return
	}

	log.Printf("[scheduler] daily commission settlement completed for %s", yesterday.Format("2006-01-02"))
}
