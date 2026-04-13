package ws

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"sync"

	"github.com/gorilla/websocket"
	"github.com/redis/go-redis/v9"

	"tongxin-go/internal/model"
	"tongxin-go/internal/service"
)

func wsHasMetadata(m json.RawMessage) bool {
	if len(m) == 0 {
		return false
	}
	s := strings.TrimSpace(string(m))
	return s != "" && s != "null" && s != "{}"
}

// Redis Pub/Sub channel for fan-out only. Payload is still written to Postgres first.
const redisChatEventsChannel = "tongxin:chat:events"

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin:     func(r *http.Request) bool { return true },
}

type ChatHub struct {
	clients map[string]map[*Client]struct{} // userID -> clients
	mu      sync.RWMutex
	msgSvc  *service.MessageService
	userSvc *service.UserService
	rdb     *redis.Client // optional: multi-instance WebSocket delivery
}

// NewChatHub creates a chat hub. rdb may be nil (single-process: broadcast stays in-memory only).
func NewChatHub(msgSvc *service.MessageService, userSvc *service.UserService, rdb *redis.Client) *ChatHub {
	return &ChatHub{
		clients: make(map[string]map[*Client]struct{}),
		msgSvc:  msgSvc,
		userSvc: userSvc,
		rdb:     rdb,
	}
}

// RunRedisSubscriber listens for fan-out events from other API instances. Cancel ctx on shutdown.
func (h *ChatHub) RunRedisSubscriber(ctx context.Context) {
	if h.rdb == nil {
		return
	}
	sub := h.rdb.Subscribe(ctx, redisChatEventsChannel)
	defer sub.Close()

	ch := sub.Channel()
	log.Printf("[chat-ws] redis subscriber listening on %s", redisChatEventsChannel)
	for {
		select {
		case <-ctx.Done():
			log.Println("[chat-ws] redis subscriber stopped")
			return
		case msg, ok := <-ch:
			if !ok {
				return
			}
			if msg == nil {
				continue
			}
			h.deliverFromRedis([]byte(msg.Payload))
		}
	}
}

type chatRedisEnvelope struct {
	MemberIDs []string       `json:"member_ids"`
	Frame     map[string]any `json:"frame"`
}

func (h *ChatHub) deliverFromRedis(raw []byte) {
	var env chatRedisEnvelope
	if err := json.Unmarshal(raw, &env); err != nil {
		return
	}
	h.broadcastToLocalMembers(env.MemberIDs, env.Frame)
}

func (h *ChatHub) broadcastToLocalMembers(memberIDs []string, frame map[string]any) {
	if len(memberIDs) == 0 || frame == nil {
		return
	}
	h.mu.RLock()
	defer h.mu.RUnlock()
	for _, memberID := range memberIDs {
		if userClients, ok := h.clients[memberID]; ok {
			for c := range userClients {
				c.SendJSON(frame)
			}
		}
	}
}

func (h *ChatHub) publishChatFanout(ctx context.Context, memberIDs []string, frame map[string]any) {
	if len(memberIDs) == 0 || frame == nil {
		return
	}
	if h.rdb == nil {
		h.broadcastToLocalMembers(memberIDs, frame)
		return
	}
	env := chatRedisEnvelope{MemberIDs: memberIDs, Frame: frame}
	b, err := json.Marshal(env)
	if err != nil {
		log.Printf("[chat-ws] redis marshal: %v", err)
		h.broadcastToLocalMembers(memberIDs, frame)
		return
	}
	if err := h.rdb.Publish(ctx, redisChatEventsChannel, b).Err(); err != nil {
		log.Printf("[chat-ws] redis publish: %v (fallback local)", err)
		h.broadcastToLocalMembers(memberIDs, frame)
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
	if _, ok := h.clients[userID]; !ok {
		h.clients[userID] = make(map[*Client]struct{})
	}
	h.clients[userID][client] = struct{}{}
	connectionCount := len(h.clients[userID])
	h.mu.Unlock()

	log.Printf("[chat-ws] client connected: %s (connections: %d)", userID, connectionCount)

	go client.WritePump()
	client.ReadPump(h.onMessage)

	h.mu.Lock()
	if userClients, ok := h.clients[userID]; ok {
		delete(userClients, client)
		if len(userClients) == 0 {
			delete(h.clients, userID)
		}
	}
	remainingConnections := len(h.clients[userID])
	h.mu.Unlock()

	log.Printf("[chat-ws] client disconnected: %s (connections: %d)", userID, remainingConnections)
}

type wsMessage struct {
	Type             string          `json:"type"`
	ConversationID   string          `json:"conversation_id,omitempty"`
	ConversationIDs  []string        `json:"conversation_ids,omitempty"`
	Content          string          `json:"content,omitempty"`
	MessageType      string          `json:"message_type,omitempty"`
	MediaURL         string          `json:"media_url,omitempty"`
	Metadata         json.RawMessage `json:"metadata,omitempty"`
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
	ids := append([]string{}, msg.ConversationIDs...)
	if msg.ConversationID != "" {
		ids = append(ids, msg.ConversationID)
	}
	seen := make(map[string]struct{})
	var uniq []string
	for _, id := range ids {
		id = strings.TrimSpace(id)
		if id == "" {
			continue
		}
		if _, ok := seen[id]; ok {
			continue
		}
		seen[id] = struct{}{}
		uniq = append(uniq, id)
		client.Subscribe(id)
	}
	if len(uniq) == 0 {
		return
	}
	client.SendJSON(map[string]any{
		"type":              "subscribed",
		"conversation_ids":  uniq,
		"conversation_id":   uniq[0],
	})
}

func (h *ChatHub) handleSend(client *Client, msg wsMessage) {
	if msg.ConversationID == "" || (strings.TrimSpace(msg.Content) == "" && !wsHasMetadata(msg.Metadata)) {
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
		Metadata:       msg.Metadata,
	}

	saved, err := h.msgSvc.SendMessage(ctx, client.UserID(), req)
	if err != nil {
		if err == service.ErrNotConversationMember {
			client.SendJSON(map[string]string{"type": "error", "message": "forbidden"})
			return
		}
		client.SendJSON(map[string]string{"type": "error", "message": "send failed"})
		return
	}

	senderName := ""
	if user, err := h.userSvc.GetProfile(ctx, client.UserID()); err == nil {
		senderName = user.DisplayName
	}
	saved.SenderName = senderName

	memberIDs, err := h.msgSvc.GetMemberIDs(ctx, msg.ConversationID)
	if err != nil {
		return
	}

	frame := map[string]any{
		"type":    "new_message",
		"message": saved,
	}
	h.publishChatFanout(ctx, memberIDs, frame)
}

func (h *ChatHub) handleTyping(client *Client, msg wsMessage) {
	if msg.ConversationID == "" {
		return
	}

	memberIDs, err := h.msgSvc.GetMemberIDs(context.Background(), msg.ConversationID)
	if err != nil {
		return
	}

	frame := map[string]any{
		"type":            "typing",
		"conversation_id": msg.ConversationID,
		"user_id":         client.UserID(),
	}

	var recipients []string
	for _, memberID := range memberIDs {
		if memberID != client.UserID() {
			recipients = append(recipients, memberID)
		}
	}
	h.publishChatFanout(context.Background(), recipients, frame)
}

// PublishNewMessageREST notifies all conversation members after POST /api/messages persisted a row.
// The app sends via HTTP, not WS handleSend — without this, other members never get new_message.
func (h *ChatHub) PublishNewMessageREST(ctx context.Context, conversationID string, msg *model.Message, senderUID string) {
	if h == nil || msg == nil || conversationID == "" {
		return
	}
	senderName := strings.TrimSpace(msg.SenderName)
	if senderName == "" && h.userSvc != nil {
		if user, err := h.userSvc.GetProfile(ctx, senderUID); err == nil {
			senderName = strings.TrimSpace(user.DisplayName)
		}
	}
	msg.SenderName = senderName
	memberIDs, err := h.msgSvc.GetMemberIDs(ctx, conversationID)
	if err != nil {
		log.Printf("[chat-ws] PublishNewMessageREST get members: %v", err)
		return
	}
	frame := map[string]any{
		"type":    "new_message",
		"message": msg,
	}
	h.publishChatFanout(ctx, memberIDs, frame)
}

// BroadcastToUser sends a payload to a user if they have a local WS (or via Redis fan-out).
func (h *ChatHub) BroadcastToUser(userID string, payload any) {
	if userID == "" {
		return
	}
	var frame map[string]any
	switch p := payload.(type) {
	case map[string]any:
		frame = p
	default:
		b, err := json.Marshal(payload)
		if err != nil {
			return
		}
		if err := json.Unmarshal(b, &frame); err != nil {
			return
		}
	}
	h.publishChatFanout(context.Background(), []string{userID}, frame)
}
