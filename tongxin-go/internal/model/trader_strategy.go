package model

import "time"

// ── Trader Strategy (published articles) ──

type TraderStrategy struct {
	ID          string    `json:"id"`
	AuthorID    string    `json:"author_id"`
	Title       string    `json:"title"`
	Summary     string    `json:"summary"`
	ContentHTML string    `json:"content_html"`
	CoverImage  string    `json:"cover_image,omitempty"`
	Category    string    `json:"category,omitempty"`
	Tags        []string  `json:"tags,omitempty"`
	Status      string    `json:"status"`
	Views       int       `json:"views"`
	Likes       int       `json:"likes"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
	// JOIN fields
	AuthorName   string `json:"author_name,omitempty"`
	AuthorAvatar string `json:"author_avatar,omitempty"`
	IsTrader     bool   `json:"is_trader,omitempty"`
}

type CreateTraderStrategyRequest struct {
	Title       string   `json:"title"`
	Summary     string   `json:"summary"`
	ContentHTML string   `json:"content_html"`
	CoverImage  string   `json:"cover_image,omitempty"`
	Category    string   `json:"category,omitempty"`
	Tags        []string `json:"tags,omitempty"`
	Status      string   `json:"status,omitempty"` // "draft" or "published"
}

type UpdateTraderStrategyRequest struct {
	Title       *string  `json:"title,omitempty"`
	Summary     *string  `json:"summary,omitempty"`
	ContentHTML *string  `json:"content_html,omitempty"`
	CoverImage  *string  `json:"cover_image,omitempty"`
	Category    *string  `json:"category,omitempty"`
	Tags        []string `json:"tags,omitempty"`
	Status      *string  `json:"status,omitempty"`
}
