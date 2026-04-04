package ws

import (
	"log"
	"net/http"
	"sync"
)

type TradingHub struct {
	clients map[string]*Client // userID -> client
	mu      sync.RWMutex
}

func NewTradingHub() *TradingHub {
	return &TradingHub{
		clients: make(map[string]*Client),
	}
}

func (h *TradingHub) HandleWS(w http.ResponseWriter, r *http.Request, userID string) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("[trading-ws] upgrade error: %v", err)
		return
	}

	client := NewClient(conn, userID)

	h.mu.Lock()
	if old, ok := h.clients[userID]; ok {
		old.Close()
	}
	h.clients[userID] = client
	h.mu.Unlock()

	log.Printf("[trading-ws] client connected: %s", userID)

	client.SendJSON(map[string]string{"type": "connected"})

	go client.WritePump()
	client.ReadPump(h.onMessage)

	h.mu.Lock()
	if h.clients[userID] == client {
		delete(h.clients, userID)
	}
	h.mu.Unlock()

	log.Printf("[trading-ws] client disconnected: %s", userID)
}

func (h *TradingHub) onMessage(client *Client, raw []byte) {
	// Any message from client resets the read deadline (keepalive).
	// Client sends JSON { "type": "ping" } for heartbeat.
	client.ResetReadDeadline()
	client.SendJSON(map[string]string{"type": "pong"})
}

// PushToUser sends a trading event to a specific user if connected.
func (h *TradingHub) PushToUser(userID string, payload any) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	if c, ok := h.clients[userID]; ok {
		c.SendJSON(payload)
	}
}
