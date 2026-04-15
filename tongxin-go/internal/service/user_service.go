package service

import (
	"context"
	"errors"
	"fmt"
	"net/mail"
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

func (s *UserService) ChangePassword(ctx context.Context, uid, currentPassword, newPassword string) error {
	if len(newPassword) < 6 {
		return errors.New("new password must be at least 6 characters")
	}
	_, hash, err := s.repo.GetPasswordHashByUID(ctx, uid)
	if err != nil {
		return errors.New("user not found")
	}
	if hash == "" {
		return errors.New("password login is not available for this account")
	}
	if err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(currentPassword)); err != nil {
		return errors.New("current password is incorrect")
	}
	if err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(newPassword)); err == nil {
		return errors.New("new password cannot match current password")
	}
	newHash, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	return s.repo.UpdatePasswordHash(ctx, uid, string(newHash))
}

func (s *UserService) ChangeEmail(ctx context.Context, uid, newEmail, currentPassword string) (*model.User, error) {
	if _, err := mail.ParseAddress(newEmail); err != nil {
		return nil, errors.New("invalid email address")
	}

	user, err := s.repo.GetByUID(ctx, uid)
	if err != nil {
		return nil, errors.New("user not found")
	}
	if user.Status != "active" {
		return nil, errors.New("account is not active")
	}
	if user.Email == newEmail {
		return nil, errors.New("new email must be different")
	}

	_, hash, err := s.repo.GetPasswordHashByUID(ctx, uid)
	if err != nil {
		return nil, errors.New("user not found")
	}
	if hash == "" {
		return nil, errors.New("password login is not available for this account")
	}
	if err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(currentPassword)); err != nil {
		return nil, errors.New("current password is incorrect")
	}

	if _, err := s.repo.GetByEmail(ctx, newEmail); err == nil {
		return nil, errors.New("email already registered")
	}

	if err := s.repo.UpdateEmail(ctx, uid, newEmail); err != nil {
		return nil, err
	}
	return s.repo.GetByUID(ctx, uid)
}

func (s *UserService) CheckDeleteAccount(ctx context.Context, uid string) (*model.DeleteAccountCheckResponse, error) {
	reasons, err := s.repo.GetDeleteAccountReasons(ctx, uid)
	if err != nil {
		return nil, err
	}
	return &model.DeleteAccountCheckResponse{
		CanDelete: len(reasons) == 0,
		Reasons:   reasons,
	}, nil
}

func (s *UserService) DeleteAccount(ctx context.Context, uid, currentPassword string) error {
	user, err := s.repo.GetByUID(ctx, uid)
	if err != nil {
		return errors.New("user not found")
	}
	if user.Status != "active" {
		return errors.New("account is not active")
	}

	_, hash, err := s.repo.GetPasswordHashByUID(ctx, uid)
	if err != nil {
		return errors.New("user not found")
	}
	if hash == "" {
		return errors.New("password login is not available for this account")
	}
	if err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(currentPassword)); err != nil {
		return errors.New("current password is incorrect")
	}

	check, err := s.CheckDeleteAccount(ctx, uid)
	if err != nil {
		return err
	}
	if !check.CanDelete {
		return fmt.Errorf("account cannot be deleted: %v", check.Reasons)
	}

	archivedEmail := fmt.Sprintf("deleted+%s+%d@deleted.local", uid, time.Now().Unix())
	return s.repo.SoftDeleteAccount(ctx, uid, archivedEmail)
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

// ResetPassword hashes the given plaintext and writes it to the user.
// Used by admins to reset a user's password.
func (s *UserService) ResetPassword(ctx context.Context, uid, password string) error {
	if len(password) < 4 {
		return errors.New("password must be at least 4 characters")
	}
	if len(password) > 72 {
		// bcrypt's hard limit is 72 bytes; reject early so the user gets a clear message.
		return errors.New("password must be at most 72 characters")
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	return s.repo.UpdatePasswordHash(ctx, uid, string(hash))
}

func (s *UserService) SetSupportAgent(ctx context.Context, uid string, enabled bool) (*model.User, error) {
	user, err := s.repo.GetByUID(ctx, uid)
	if err != nil {
		return nil, errors.New("user not found")
	}
	if user.Status != "active" {
		return nil, errors.New("only active users can be support agents")
	}
	if err := s.repo.SetSupportAgent(ctx, uid, enabled); err != nil {
		return nil, err
	}
	return s.repo.GetByUID(ctx, uid)
}

func (s *UserService) ListSupportAgents(ctx context.Context) ([]model.User, error) {
	return s.repo.ListSupportAgents(ctx)
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
