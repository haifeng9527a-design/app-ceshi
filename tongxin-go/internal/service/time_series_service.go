package service

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"tongxin-go/internal/model"
	"tongxin-go/internal/repository"
)

// TimeSeriesService Sprint 3 / M4：多指标时间序列聚合。
//
// 职责：
//   - 参数规整（默认值、上限、粒度合法性）
//   - 调度 repo 并发查询多个 metric
//   - 日期补零（空 bucket 补 0）
//   - 转成前端可消费的 Series（label/unit 映射）
//
// 不在这层做的：具体 SQL 表达；时区换算（统一 UTC）。
type TimeSeriesService struct {
	repo *repository.TimeSeriesRepo
}

func NewTimeSeriesService(repo *repository.TimeSeriesRepo) *TimeSeriesService {
	return &TimeSeriesService{repo: repo}
}

// TimeSeriesInput handler 层构造；service 做剩余校验。
type TimeSeriesInput struct {
	AgentUID    string
	Metrics     []string
	From        time.Time
	To          time.Time
	Granularity string
}

// 单次请求最多 4 条 metric；重复的只算一次。
const maxMetricsPerRequest = 4

// Query 多指标聚合：每个 metric 走一条独立 SQL（数据量小，多查询影响可忽略）。
// 返回的 Points 已按 granularity 补零 → 前端可以无脑画折线。
func (s *TimeSeriesService) Query(ctx context.Context, in *TimeSeriesInput) (*model.TimeSeriesResponse, error) {
	if in == nil || in.AgentUID == "" {
		return nil, errors.New("agent uid required")
	}
	if !repository.ValidGranularity(in.Granularity) {
		return nil, repository.ErrTimeSeriesBadGranularity
	}
	if in.From.After(in.To) {
		return nil, repository.ErrTimeSeriesBadRange
	}

	metrics := dedupMetrics(in.Metrics)
	if len(metrics) == 0 {
		// 默认全部 4 个
		for _, m := range model.SupportedTimeSeriesMetrics {
			metrics = append(metrics, m.Metric)
		}
	}
	if len(metrics) > maxMetricsPerRequest {
		metrics = metrics[:maxMetricsPerRequest]
	}

	metaByMetric := make(map[string]model.TimeSeriesMetricMeta, len(model.SupportedTimeSeriesMetrics))
	for _, m := range model.SupportedTimeSeriesMetrics {
		metaByMetric[m.Metric] = m
	}

	series := make([]model.TimeSeriesSeries, 0, len(metrics))
	for _, metric := range metrics {
		meta, ok := metaByMetric[metric]
		if !ok {
			return nil, fmt.Errorf("unsupported metric: %s", metric)
		}
		points, err := s.repo.QueryMetric(ctx, repository.TimeSeriesQuery{
			AgentUID:    in.AgentUID,
			Metric:      metric,
			From:        in.From,
			To:          in.To,
			Granularity: in.Granularity,
		})
		if err != nil {
			return nil, err
		}
		// 补零 + 计算总和
		filled := fillMissingBuckets(points, in.From, in.To, in.Granularity)
		total := 0.0
		for _, p := range filled {
			total += p.Value
		}
		series = append(series, model.TimeSeriesSeries{
			Metric: metric,
			Label:  meta.Label,
			Unit:   meta.Unit,
			Total:  total,
			Points: filled,
		})
	}

	return &model.TimeSeriesResponse{
		From:        in.From.UTC().Format("2006-01-02"),
		To:          in.To.UTC().Format("2006-01-02"),
		Granularity: in.Granularity,
		Series:      series,
	}, nil
}

// ── helpers ──

// dedupMetrics 去重 + 去空串 + 去首尾空格。
func dedupMetrics(metrics []string) []string {
	seen := make(map[string]struct{}, len(metrics))
	out := make([]string, 0, len(metrics))
	for _, m := range metrics {
		m = strings.TrimSpace(m)
		if m == "" {
			continue
		}
		if _, ok := seen[m]; ok {
			continue
		}
		seen[m] = struct{}{}
		out = append(out, m)
	}
	return out
}

// fillMissingBuckets 按 granularity 生成完整日期轴，空 bucket 补 0。
// 保证前端 recharts 不会断线 / 日期跳跃。
func fillMissingBuckets(
	points []model.TimeSeriesPoint, from, to time.Time, granularity string,
) []model.TimeSeriesPoint {
	byDate := make(map[string]float64, len(points))
	for _, p := range points {
		byDate[p.Date] = p.Value
	}

	// 起点对齐到 bucket 边界
	start := truncToBucket(from, granularity)
	// 结束包含 to 当天 / 当周 / 当月
	end := truncToBucket(to, granularity)

	out := make([]model.TimeSeriesPoint, 0, 64)
	for t := start; !t.After(end); t = advanceBucket(t, granularity) {
		key := t.UTC().Format("2006-01-02")
		out = append(out, model.TimeSeriesPoint{
			Date:  key,
			Value: byDate[key], // map missing = 0
		})
	}
	return out
}

func truncToBucket(t time.Time, granularity string) time.Time {
	t = t.UTC()
	switch granularity {
	case "day":
		return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC)
	case "week":
		// ISO 周：周一为起点。Go 的 Weekday(): Sunday=0, Monday=1, ...
		wd := int(t.Weekday())
		if wd == 0 {
			wd = 7
		}
		return time.Date(t.Year(), t.Month(), t.Day()-(wd-1), 0, 0, 0, 0, time.UTC)
	case "month":
		return time.Date(t.Year(), t.Month(), 1, 0, 0, 0, 0, time.UTC)
	default:
		return t
	}
}

func advanceBucket(t time.Time, granularity string) time.Time {
	switch granularity {
	case "day":
		return t.AddDate(0, 0, 1)
	case "week":
		return t.AddDate(0, 0, 7)
	case "month":
		return t.AddDate(0, 1, 0)
	default:
		return t.AddDate(0, 0, 1)
	}
}
