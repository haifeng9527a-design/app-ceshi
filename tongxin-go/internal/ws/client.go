package ws

import (
	"encoding/json"
	"log"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

const (
	writeWait  = 10 * time.Second
	pongWait   = 60 * time.Second
	pingPeriod = 25 * time.Second
	maxMsgSize = 4096
)

type Client struct {
	conn    *websocket.Conn
	send    chan []byte
	userID  string
	subs    map[string]bool // subscribed conversation/symbol IDs
	subsMu  sync.RWMutex
	closeCh chan struct{}
	once    sync.Once
}

func NewClient(conn *websocket.Conn, userID string) *Client {
	return &Client{
		conn:    conn,
		send:    make(chan []byte, 256),
		userID:  userID,
		subs:    make(map[string]bool),
		closeCh: make(chan struct{}),
	}
}

func (c *Client) UserID() string { return c.userID }

func (c *Client) Subscribe(id string) {
	c.subsMu.Lock()
	c.subs[id] = true
	c.subsMu.Unlock()
}

func (c *Client) Unsubscribe(id string) {
	c.subsMu.Lock()
	delete(c.subs, id)
	c.subsMu.Unlock()
}

func (c *Client) IsSubscribed(id string) bool {
	c.subsMu.RLock()
	defer c.subsMu.RUnlock()
	return c.subs[id]
}

func (c *Client) ResetReadDeadline() {
	c.conn.SetReadDeadline(time.Now().Add(pongWait))
}

func (c *Client) Send(data []byte) {
	select {
	case <-c.closeCh:
		return
	default:
	}

	select {
	case c.send <- data:
	case <-c.closeCh:
	default:
		log.Printf("[ws] client %s send buffer full, closing socket for clean reconnect", c.userID)
		c.Close()
	}
}

func (c *Client) SendJSON(v any) {
	data, err := json.Marshal(v)
	if err != nil {
		return
	}
	c.Send(data)
}

func (c *Client) Close() {
	c.once.Do(func() {
		close(c.closeCh)
		c.conn.Close()
	})
}

func (c *Client) WritePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		if r := recover(); r != nil {
			log.Printf("[ws] WritePump panic recovered for %s: %v", c.userID, r)
		}
		ticker.Stop()
		c.Close()
	}()

	for {
		select {
		case msg := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.TextMessage, msg); err != nil {
				return
			}
		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		case <-c.closeCh:
			return
		}
	}
}

func (c *Client) ReadPump(onMessage func(*Client, []byte)) {
	defer c.Close()
	c.conn.SetReadLimit(maxMsgSize)
	c.conn.SetReadDeadline(time.Now().Add(pongWait))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	for {
		_, msg, err := c.conn.ReadMessage()
		if err != nil {
			return
		}
		onMessage(c, msg)
	}
}
