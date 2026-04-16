package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/chromedp/chromedp"

	"tongxin-go/internal/middleware"
	"tongxin-go/internal/model"
	"tongxin-go/internal/repository"
)

// WeeklyReportService Sprint 5：周报生成。
//
// 生成流程：
//  1. 查本周（UTC 周一 00:00 ~ 下周一 00:00）聚合数据
//  2. 把数据塞进内存 cache，key = 短时 JWT token（60s 有效）
//  3. chromedp 启 headless chromium → 访问 /weekly-report-render?token=...
//  4. 前端页面拿 token → 回调 GET /api/agent/weekly-report/render-data?token=...
//     → 渲染 1080×1920 海报
//  5. chromedp 截图 PNG → 写入 {StoragePath}/weekly-reports/{uid}/{yyyyww}.png
//  6. notification.Create({kind:'weekly_report', payload:{png_url, week_label, ...}})
//
// Fallback 设计：
//   - 环境变量 WEEKLY_REPORT_CHROMEDP=false（默认 true）→ 跳过 chromedp 截图，PNG URL 为空
//   - chromedp 执行失败 → log WARN，仍写 notification 但 png_url 为空
//     前端周报点开就只显示文字摘要，不崩溃。
//
// 可配置：
//   - WEEKLY_REPORT_FRONTEND_URL：chromedp 打开的前端 URL（默认 http://localhost:3030）
//   - WEEKLY_REPORT_STORAGE_DIR：PNG 输出目录（默认 {StoragePath}/weekly-reports）
type WeeklyReportService struct {
	repo            *repository.WeeklyReportRepo
	notificationSvc *NotificationService
	jwtSecret       []byte
	storageDir      string // PNG 落盘目录
	staticBaseURL   string // 外部可访问的 /uploads 根路径（生成 png_url 用）
	frontendURL     string // 前端 /weekly-report-render 的 base URL（chromedp 访问）
	chromedpEnabled bool

	// 内存缓存 token → WeeklyReportData。
	// cron 一轮生成几十/几百 agent，每个 token 60s 过期。并发安全 + 过期自清。
	cache sync.Map // map[string]*cachedReport
}

type cachedReport struct {
	data      *model.WeeklyReportData
	expiresAt time.Time
}

func NewWeeklyReportService(
	repo *repository.WeeklyReportRepo,
	notificationSvc *NotificationService,
	jwtSecret []byte,
	storageDir string,
	staticBaseURL string,
	frontendURL string,
	chromedpEnabled bool,
) *WeeklyReportService {
	if storageDir == "" {
		storageDir = "./uploads/weekly-reports"
	}
	if staticBaseURL == "" {
		staticBaseURL = "/uploads/weekly-reports"
	}
	if frontendURL == "" {
		frontendURL = "http://localhost:3030"
	}
	return &WeeklyReportService{
		repo:            repo,
		notificationSvc: notificationSvc,
		jwtSecret:       jwtSecret,
		storageDir:      storageDir,
		staticBaseURL:   staticBaseURL,
		frontendURL:     frontendURL,
		chromedpEnabled: chromedpEnabled,
	}
}

// ComputeWeekRange 把参考时刻换算成 ISO 周窗口：[周一 00:00 UTC, 下周一 00:00 UTC)。
// 传 time.Now() 得到「本周」；传 time.Now().AddDate(0,0,-7) 得到「上周」。
func ComputeWeekRange(ref time.Time) (from, to time.Time, label string) {
	ref = ref.UTC()
	wd := int(ref.Weekday()) // Sunday=0
	if wd == 0 {
		wd = 7
	}
	from = time.Date(ref.Year(), ref.Month(), ref.Day()-(wd-1), 0, 0, 0, 0, time.UTC)
	to = from.AddDate(0, 0, 7)
	_, week := from.ISOWeek()
	label = fmt.Sprintf("Week %d, %d", week, from.Year())
	return
}

// Generate 查询数据 + 渲染 PNG + 写通知。返回生成的 report（含 png_url）。
// 用 opt 控制：agentUID（必填）、weekRef（用哪周，默认上周 = now-7d）。
func (s *WeeklyReportService) Generate(
	ctx context.Context, agentUID string, weekRef time.Time,
) (*model.WeeklyReportData, string, error) {
	if agentUID == "" {
		return nil, "", errors.New("agent uid required")
	}
	if weekRef.IsZero() {
		weekRef = time.Now().AddDate(0, 0, -7) // 默认上周
	}

	from, to, label := ComputeWeekRange(weekRef)

	// 1) meta
	meta, err := s.repo.GetAgentMeta(ctx, agentUID)
	if err != nil {
		return nil, "", fmt.Errorf("get agent meta: %w", err)
	}

	// 2) 并发跑三条查询（7d 数据量小，但显式并发仍有收益）
	var (
		indicators model.WeeklyReportIndicators
		trend      []model.WeeklyReportDailyPoint
		top        []model.WeeklyReportTopInvitee
		indErr     error
		trendErr   error
		topErr     error
	)
	var wg sync.WaitGroup
	wg.Add(3)
	go func() {
		defer wg.Done()
		indicators, indErr = s.repo.QueryWeeklyIndicators(ctx, agentUID, from, to)
	}()
	go func() {
		defer wg.Done()
		trend, trendErr = s.repo.QueryDailyTrend(ctx, agentUID, from, to)
	}()
	go func() {
		defer wg.Done()
		top, topErr = s.repo.QueryTopInvitees(ctx, agentUID, from, to, 5)
	}()
	wg.Wait()

	if indErr != nil {
		return nil, "", indErr
	}
	if trendErr != nil {
		return nil, "", trendErr
	}
	if topErr != nil {
		return nil, "", topErr
	}

	report := &model.WeeklyReportData{
		AgentUID:      agentUID,
		AgentName:     meta.DisplayName,
		AgentEmail:    meta.Email,
		WeekStartISO:  from.Format("2006-01-02"),
		WeekEndISO:    to.AddDate(0, 0, -1).Format("2006-01-02"),
		WeekLabel:     label,
		GeneratedAtMS: time.Now().UnixMilli(),
		Indicators:    indicators,
		TrendDaily:    trend,
		TopInvitees:   top,
	}

	// 3) 签短时 token，缓存 report → chromedp 访问
	token, err := middleware.SignJWT(map[string]any{
		"uid":   agentUID,
		"scope": "weekly_report_render",
	}, s.jwtSecret, 90*time.Second) // 多给 30s 余量
	if err != nil {
		return nil, "", fmt.Errorf("sign weekly report token: %w", err)
	}
	s.cache.Store(token, &cachedReport{
		data:      report,
		expiresAt: time.Now().Add(90 * time.Second),
	})

	// 4) 截图（可选）
	pngURL, err := s.renderPNG(ctx, agentUID, from, token)
	if err != nil {
		// 降级：写通知但 png_url 为空
		log.Printf("[weekly-report] render PNG for %s failed: %v (fallback to text-only notification)", agentUID, err)
		pngURL = ""
	}

	// 5) 通知
	if s.notificationSvc != nil {
		payload := map[string]any{
			"png_url":     pngURL,
			"week_label":  report.WeekLabel,
			"week_start":  report.WeekStartISO,
			"week_end":    report.WeekEndISO,
			"commission":  report.Indicators.CommissionUSDT,
			"new_ivtees":  report.Indicators.NewInvitees,
			"agent_uid":   agentUID,
		}
		payloadBytes, _ := json.Marshal(payload)
		if _, nerr := s.notificationSvc.Create(ctx, &model.CreateNotificationInput{
			UserUID: agentUID,
			Kind:    "weekly_report",
			Title:   fmt.Sprintf("周报：%s", report.WeekLabel),
			Body: fmt.Sprintf(
				"本周获返佣 %.2f USDT，新增下级 %d 人，活跃下级 %d 人",
				report.Indicators.CommissionUSDT,
				report.Indicators.NewInvitees,
				report.Indicators.ActiveInvitees,
			),
			Payload: payloadBytes,
		}); nerr != nil {
			return report, pngURL, fmt.Errorf("create weekly report notification: %w", nerr)
		}
	}

	return report, pngURL, nil
}

// ConsumeRenderToken 前端渲染页面拿 token 来换 data。单次命中后仍保留（chromedp 可能重试）。
// token 过期返回 nil。
func (s *WeeklyReportService) ConsumeRenderToken(token string) *model.WeeklyReportData {
	v, ok := s.cache.Load(token)
	if !ok {
		return nil
	}
	cr, ok := v.(*cachedReport)
	if !ok {
		return nil
	}
	if time.Now().After(cr.expiresAt) {
		s.cache.Delete(token)
		return nil
	}
	return cr.data
}

// renderPNG 用 chromedp 访问前端页面截 1080×1920 PNG。
func (s *WeeklyReportService) renderPNG(
	ctx context.Context, agentUID string, from time.Time, token string,
) (string, error) {
	if !s.chromedpEnabled {
		return "", errors.New("chromedp disabled (WEEKLY_REPORT_CHROMEDP=false)")
	}

	// 落盘路径：{storage}/weekly-reports/{uid}/{YYYYWW}.png
	_, week := from.ISOWeek()
	filename := fmt.Sprintf("%d%02d.png", from.Year(), week)
	dir := filepath.Join(s.storageDir, agentUID)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", fmt.Errorf("mkdir weekly report dir: %w", err)
	}
	filePath := filepath.Join(dir, filename)

	renderURL := fmt.Sprintf("%s/weekly-report-render?token=%s", s.frontendURL, token)

	// chromedp allocator：headless + 1080x1920
	allocCtx, cancelAlloc := chromedp.NewExecAllocator(ctx,
		append(chromedp.DefaultExecAllocatorOptions[:],
			chromedp.WindowSize(1080, 1920),
			chromedp.Flag("headless", true),
			chromedp.Flag("disable-gpu", true),
			chromedp.Flag("no-sandbox", true),
		)...)
	defer cancelAlloc()

	chromeCtx, cancelChrome := chromedp.NewContext(allocCtx)
	defer cancelChrome()

	// 60s 超时（chromedp 冷启 + 页面 render 实测 <10s）
	timeoutCtx, cancelTimeout := context.WithTimeout(chromeCtx, 60*time.Second)
	defer cancelTimeout()

	var buf []byte
	if err := chromedp.Run(timeoutCtx,
		chromedp.EmulateViewport(1080, 1920),
		chromedp.Navigate(renderURL),
		// 等到 data-render-ready="1" 才说明前端 fetch 完数据
		chromedp.WaitVisible(`[data-render-ready="1"]`, chromedp.ByQuery),
		// CaptureScreenshot 输出 PNG（viewport 已 1080×1920）。
		// 不用 FullScreenshot：它的 quality 参数会强制 JPEG，和文件名 .png 不匹配。
		chromedp.CaptureScreenshot(&buf),
	); err != nil {
		return "", fmt.Errorf("chromedp run: %w", err)
	}

	if err := os.WriteFile(filePath, buf, 0o644); err != nil {
		return "", fmt.Errorf("write png: %w", err)
	}

	// 可访问 URL：{staticBaseURL}/{uid}/{filename}
	return fmt.Sprintf("%s/%s/%s", s.staticBaseURL, agentUID, filename), nil
}

// GenerateAll cron 入口：遍历全部 active agent 生成上周报告。单个失败不阻断其他。
// 返回 (成功数, 失败数, 详细错误前 3 条)。
func (s *WeeklyReportService) GenerateAll(ctx context.Context, weekRef time.Time) (int, int, []error) {
	uids, err := s.repo.ListActiveAgentUIDs(ctx)
	if err != nil {
		return 0, 0, []error{fmt.Errorf("list agents: %w", err)}
	}

	ok, fail := 0, 0
	errs := make([]error, 0, 3)
	for _, uid := range uids {
		genCtx, cancel := context.WithTimeout(ctx, 90*time.Second)
		_, _, err := s.Generate(genCtx, uid, weekRef)
		cancel()
		if err != nil {
			fail++
			if len(errs) < 3 {
				errs = append(errs, fmt.Errorf("agent %s: %w", uid, err))
			}
			continue
		}
		ok++
	}
	return ok, fail, errs
}
