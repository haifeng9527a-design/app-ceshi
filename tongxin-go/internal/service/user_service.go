package service

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"golang.org/x/crypto/bcrypt"
	"tongxin-go/internal/middleware"
	"tongxin-go/internal/model"
	"tongxin-go/internal/repository"
)

type UserService struct {
	repo *repository.UserRepo
}

func NewUserService(repo *repository.UserRepo) *UserService {
	return &UserService{repo: repo}
}

func (s *UserService) Register(ctx context.Context, req *model.RegisterRequest) (*model.AuthResponse, error) {
	// Check if email already exists
	_, err := s.repo.GetByEmail(ctx, req.Email)
	if err == nil {
		return nil, errors.New("email already registered")
	}

	// Hash password
	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		return nil, err
	}

	// Generate unique numeric UID with collision check
	var uid string
	for i := 0; i < 5; i++ {
		uid = generateUID()
		if _, err := s.repo.GetByUID(ctx, uid); err != nil {
			break // not found = available
		}
		if i == 4 {
			return nil, errors.New("failed to generate unique UID")
		}
	}

	u := &model.User{
		UID:         uid,
		Email:       req.Email,
		DisplayName: req.DisplayName,
	}
	if err := s.repo.Create(ctx, u, string(hash)); err != nil {
		return nil, err
	}

	user, err := s.repo.GetByUID(ctx, uid)
	if err != nil {
		return nil, err
	}

	token, err := middleware.SignJWT(map[string]any{
		"uid":   uid,
		"email": req.Email,
	}, middleware.JWTSecret, 7*24*time.Hour)
	if err != nil {
		return nil, err
	}

	return &model.AuthResponse{Token: token, User: user}, nil
}

func (s *UserService) Login(ctx context.Context, email, password string) (*model.AuthResponse, error) {
	uid, hash, err := s.repo.GetPasswordHash(ctx, email)
	if err != nil {
		return nil, errors.New("invalid email or password")
	}
	if hash == "" {
		return nil, errors.New("invalid email or password")
	}

	if err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)); err != nil {
		return nil, errors.New("invalid email or password")
	}

	user, err := s.repo.GetByUID(ctx, uid)
	if err != nil {
		return nil, err
	}

	token, err := middleware.SignJWT(map[string]any{
		"uid":   uid,
		"email": email,
	}, middleware.JWTSecret, 7*24*time.Hour)
	if err != nil {
		return nil, err
	}

	return &model.AuthResponse{Token: token, User: user}, nil
}

func (s *UserService) GetProfile(ctx context.Context, uid string) (*model.User, error) {
	return s.repo.GetByUID(ctx, uid)
}

func (s *UserService) UpdateProfile(ctx context.Context, uid string, req *model.UpdateProfileRequest) (*model.User, error) {
	if err := s.repo.Update(ctx, uid, req); err != nil {
		return nil, err
	}
	return s.repo.GetByUID(ctx, uid)
}

func (s *UserService) Search(ctx context.Context, query string, limit int) ([]model.FriendProfile, error) {
	return s.repo.Search(ctx, query, limit)
}

func (s *UserService) BatchGetProfiles(ctx context.Context, uids []string) ([]model.FriendProfile, error) {
	return s.repo.BatchGetProfiles(ctx, uids)
}

func (s *UserService) ListAll(ctx context.Context, limit, offset int) ([]model.User, int, error) {
	return s.repo.ListAll(ctx, limit, offset)
}

func (s *UserService) UpdateRole(ctx context.Context, uid, role string) error {
	return s.repo.UpdateRole(ctx, uid, role)
}

func (s *UserService) UpdateStatus(ctx context.Context, uid, status string) error {
	return s.repo.UpdateStatus(ctx, uid, status)
}

func (s *UserService) GetAdminStats(ctx context.Context) (map[string]int, error) {
	totalUsers, adminCount, traderCount, pendingApps, activeUsers, err := s.repo.GetAdminStats(ctx)
	if err != nil {
		return nil, err
	}
	return map[string]int{
		"total_users":  totalUsers,
		"admin_count":  adminCount,
		"trader_count": traderCount,
		"pending_apps": pendingApps,
		"active_users": activeUsers,
	}, nil
}

func (s *UserService) ListByRole(ctx context.Context, role string) ([]model.User, error) {
	return s.repo.ListByRole(ctx, role)
}

func (s *UserService) SearchAll(ctx context.Context, query string, limit int) ([]model.User, error) {
	return s.repo.SearchAll(ctx, query, limit)
}

func (s *UserService) AddAdmin(ctx context.Context, email string) (*model.User, error) {
	user, err := s.repo.GetByEmail(ctx, email)
	if err != nil {
		return nil, errors.New("user not found")
	}
	if user.Role == "admin" {
		return nil, errors.New("user is already an admin")
	}
	if err := s.repo.UpdateRole(ctx, user.UID, "admin"); err != nil {
		return nil, err
	}
	return s.repo.GetByUID(ctx, user.UID)
}

func (s *UserService) RemoveAdmin(ctx context.Context, uid, currentAdminUID string) error {
	if uid == currentAdminUID {
		return errors.New("cannot demote yourself")
	}
	user, err := s.repo.GetByUID(ctx, uid)
	if err != nil {
		return errors.New("user not found")
	}
	if user.Role != "admin" {
		return errors.New("user is not an admin")
	}
	return s.repo.UpdateRole(ctx, uid, "user")
}

func (s *UserService) EnsureUser(ctx context.Context, uid, email, displayName string) (*model.User, error) {
	u, err := s.repo.GetByUID(ctx, uid)
	if err != nil {
		if !errors.Is(err, pgx.ErrNoRows) {
			return nil, err
		}
		u = &model.User{
			UID:         uid,
			Email:       email,
			DisplayName: displayName,
		}
		if err := s.repo.Create(ctx, u, ""); err != nil {
			return nil, err
		}
		return s.repo.GetByUID(ctx, uid)
	}
	return u, nil
}

func generateUID() string {
	// Use timestamp + random for unique ID
	return repository.GenerateUID()
}
