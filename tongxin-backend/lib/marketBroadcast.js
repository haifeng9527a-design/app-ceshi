/**
 * 行情广播：ingestors 写入时调用，通过 chat WebSocket 推送给订阅了该 symbol 的客户端
 * 格式：{ symbol, price, size?, change?, percent_change?, market?: 'stock'|'forex'|'crypto' }
 */
const EventEmitter = require('events');
const marketBroadcast = new EventEmitter();
marketBroadcast.setMaxListeners(50);

function emitQuote(update) {
  if (!update || !update.symbol || !Number.isFinite(update.price)) return;
  marketBroadcast.emit('quote', update);
}

module.exports = { marketBroadcast, emitQuote };
