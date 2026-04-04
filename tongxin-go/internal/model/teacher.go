package model

import "time"

type Teacher struct {
	UserID        string    `json:"user_id"`
	Status        string    `json:"status"` // pending, approved, rejected
	Bio           string    `json:"bio,omitempty"`
	Specialties   []string  `json:"specialties,omitempty"`
	Rating        float64   `json:"rating"`
	FollowerCount int       `json:"follower_count"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`

	// Joined from users table
	DisplayName string `json:"display_name,omitempty"`
	AvatarURL   string `json:"avatar_url,omitempty"`
}

type Strategy struct {
	ID        string    `json:"id"`
	TeacherID string    `json:"teacher_id"`
	Title     string    `json:"title"`
	Content   string    `json:"content"`
	Images    []string  `json:"images,omitempty"`
	Category  string    `json:"category,omitempty"`
	Likes     int       `json:"likes"`
	CreatedAt time.Time `json:"created_at"`
}

type TeacherFollower struct {
	TeacherID string    `json:"teacher_id"`
	UserID    string    `json:"user_id"`
	CreatedAt time.Time `json:"created_at"`
}

type ApplyTeacherRequest struct {
	Bio         string   `json:"bio"`
	Specialties []string `json:"specialties"`
}

type CreateStrategyRequest struct {
	Title    string   `json:"title"`
	Content  string   `json:"content"`
	Images   []string `json:"images,omitempty"`
	Category string   `json:"category,omitempty"`
}
