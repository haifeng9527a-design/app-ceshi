package ws

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"sync"

	"github.com/gorilla/websocket"
	"tongxin-go/internal/model"
	"tongxin-go/internal/service"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin:     func(r *http.Request) bool { return true },
}

type ChatHub struct {
	clients  map[string]*Client // userID -> client
	mu       sync.RWMutex
	msgSvc   *service.MessageService
	userSvc  *service.UserService
}

func NewChatHub(msgSvc *service.MessageService, userSvc *service.UserService) *ChatHub {
	return &ChatHub{
		clients: make(map[string]*Client),
		msgSvc:  msgSvc,
		userSvc: userSvc,
	}
}

func (h *ChatHub) HandleWS(w http.ResponseWriter, r *http.Request, userID string) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("[chat-ws] upgrade error: %v", err)
		return
	}

	client := NewClient(conn, userID)

	h.mu.Lock()
	// Close existing connection for same user
	if old, ok := h.clients[userID]; ok {
		old.Close()
	}
	h.clients[userID] = client
	h.mu.Unlock()

	log.Printf("[chat-ws] client connected: %s", userID)

	go client.WritePump()
	client.ReadPump(h.onMessage)

	h.mu.Lock()
	if h.clients[userID] == client {
		delete(h.clients, userID)
	}
	h.mu.Unlock()

	log.Printf("[chat-ws] client disconnected: %s", userID)
}

type wsMessage struct {
	Type           string `json:"type"`
	ConversationID string `json:"conversation_id,omitempty"`
	Content        string `json:"content,omitempty"`
	MessageType    string `json:"message_type,omitempty"`
	MediaURL       string `json:"media_url,omitempty"`
}

func (h *ChatHub) onMessage(client *Client, raw []byte) {
	var msg wsMessage
	if err := json.Unmarshal(raw, &msg); err != nil {
		client.SendJSON(map[string]string{"type": "error", "message": "invalid json"})
		return
	}

	switch msg.Type {
	case "subscribe":
		h.handleSubscribe(client, msg)
	case "send":
		h.handleSend(client, msg)
	case "typing":
		h.handleTyping(client, msg)
	case "ping":
		client.SendJSON(map[string]string{"type": "pong"})
	default:
		client.SendJSON(map[string]string{"type": "error", "message": "unknown type"})
	}
}

func (h *ChatHub) handleSubscribe(client *Client, msg wsMessage) {
	if msg.ConversationID == "" {
		return
	}
	client.Subscribe(msg.ConversationID)
	client.SendJSON(map[string]string{
		"type":            "subscribed",
		"conversation_id": msg.ConversationID,
	})
}

func (h *ChatHub) handleSend(client *Client, msg wsMessage) {
	if msg.ConversationID == "" || msg.Content == "" {
		client.SendJSON(map[string]string{"type": "error", "message": "missing fields"})
		return
	}

	ctx := context.Background()

	msgType := msg.MessageType
	if msgType == "" {
		msgType = "text"
	}

	req := &model.SendMessageRequest{
		ConversationID: msg.ConversationID,
		Content:        msg.Content,
		MessageType:    msgType,
		MediaURL:       msg.MediaURL,
	}

	saved, err := h.msgSvc.SendMessage(ctx, client.UserID(), req)
	if err != nil {
		client.SendJSON(map[string]string{"type": "error", "message": "send failed"})
		return
	}

	// Get sender name
	senderName := ""
	if user, err := h.userSvc.GetProfile(ctx, client.UserID()); err == nil {
		senderName = user.DisplayName
	}
	saved.SenderName = senderName

	// Broadcast to all conversation members
	memberIDs, err := h.msgSvc.GetMemberIDs(ctx, msg.ConversationID)
	if err != nil {
		return
	}

	payload := map[string]any{
		"type":    "new_message",
		"message": saved,
	}

	h.mu.RLock()
	for _, memberID := range memberIDs {
		if c, ok := h.clients[memberID]; ok {
			c.SendJSON(payload)
		}
	}
	h.mu.RUnlock()
}

func (h *ChatHub) handleTyping(client *Client, msg wsMessage) {
	if msg.ConversationID == "" {
		return
	}

	memberIDs, err := h.msgSvc.GetMemberIDs(context.Background(), msg.ConversationID)
	if err != nil {
		return
	}

	payload := map[string]string{
		"type":            "typing",
		"conversation_id": msg.ConversationID,
		"user_id":         client.UserID(),
	}

	h.mu.RLock()
	for _, memberID := range memberIDs {
		if memberID != client.UserID() {
			if c, ok := h.clients[memberID]; ok {
				c.SendJSON(payload)
			}
		}
	}
	h.mu.RUnlock()
}

// BroadcastToUser sends a message to a specific user if connected
func (h *ChatHub) BroadcastToUser(userID string, payload any) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	if c, ok := h.clients[userID]; ok {
		c.SendJSON(payload)
	}
}
