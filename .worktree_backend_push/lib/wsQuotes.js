/**
 * WebSocket 行情代理：前端连后端，后端连 Polygon
 * 路径：/ws/quotes
 * 前端发送：{ action: 'subscribe', symbols: ['AAPL','MSFT'] }
 * 后端转发 Polygon 成交推送：{ ev: 'T', sym, p, s, t }
 */
const WebSocket = require('ws');

const POLYGON_WS = 'wss://socket.polygon.io/stocks';

function createQuotesWsServer(httpServer, polygonKey) {
  if (!polygonKey) {
    console.warn('[wsQuotes] POLYGON_API_KEY 未配置，WebSocket 行情代理未启动');
    return;
  }

  const wss = new WebSocket.Server({ path: '/ws/quotes', noServer: true });

  httpServer.on('upgrade', (request, socket, head) => {
    const url = new URL(request.url || '', `http://${request.headers.host}`);
    if (url.pathname !== '/ws/quotes') return;
    wss.handleUpgrade(request, socket, head, (ws) => {
      wss.emit('connection', ws, request);
    });
  });

  wss.on('connection', (clientWs) => {
    let polygonWs = null;

    function connectPolygon(symbols) {
      if (!symbols || symbols.length === 0) return;
      if (polygonWs && polygonWs.readyState === WebSocket.OPEN) {
        for (const sym of symbols) {
          polygonWs.send(JSON.stringify({ action: 'subscribe', params: `T.${sym}` }));
        }
        return;
      }

      polygonWs = new WebSocket(POLYGON_WS);
      polygonWs.on('open', () => {
        polygonWs.send(JSON.stringify({ action: 'auth', params: polygonKey }));
        for (const sym of symbols) {
          polygonWs.send(JSON.stringify({ action: 'subscribe', params: `T.${sym}` }));
        }
      });
      polygonWs.on('message', (data) => {
        if (clientWs.readyState === WebSocket.OPEN) {
          clientWs.send(data.toString());
        }
      });
      polygonWs.on('error', (err) => {
        console.error('[wsQuotes] Polygon error:', err.message);
      });
      polygonWs.on('close', () => {
        polygonWs = null;
      });
    }

    function unsubscribeAll() {
      if (polygonWs && polygonWs.readyState === WebSocket.OPEN) {
        polygonWs.close();
        polygonWs = null;
      }
    }

    clientWs.on('message', (data) => {
      try {
        const msg = JSON.parse(data.toString());
        if (msg.action === 'subscribe' && Array.isArray(msg.symbols)) {
          const raw = msg.symbols.map((s) => String(s).trim().toUpperCase()).filter((s) => s.length > 0);
          const symbols = raw.filter((s) => s !== '*').slice(0, 30);
          if (symbols.length === 0) return;
          connectPolygon(symbols);
        } else if (msg.action === 'unsubscribe') {
          unsubscribeAll();
        }
      } catch (_) {}
    });

    clientWs.on('close', () => {
      unsubscribeAll();
    });

    clientWs.on('error', () => {
      unsubscribeAll();
    });
  });

  console.log('[wsQuotes] WebSocket 行情代理已启动，路径 /ws/quotes');
}

module.exports = { createQuotesWsServer };
