// 技术指标计算（纯 Dart，无 UI 依赖）
// 输入：收盘价/成交量序列；输出：指标序列

/// MA（简单移动平均）
/// [closes] 收盘价序列，返回与 closes 等长，前 period-1 个为 null
List<double?> ma(List<double> closes, int period) {
  if (closes.isEmpty || period < 1) return [];
  final out = <double?>[];
  for (var i = 0; i < closes.length; i++) {
    if (i < period - 1) {
      out.add(null);
      continue;
    }
    double sum = 0;
    for (var j = 0; j < period; j++) sum += closes[i - j];
    out.add(sum / period);
  }
  return out;
}

/// EMA（指数移动平均）
/// alpha = 2/(period+1)，首根 EMA 取前 period 根的 SMA
List<double?> ema(List<double> closes, int period) {
  if (closes.isEmpty || period < 1) return [];
  final out = <double?>[];
  final alpha = 2.0 / (period + 1);
  for (var i = 0; i < closes.length; i++) {
    if (i < period - 1) {
      out.add(null);
      continue;
    }
    if (i == period - 1) {
      double sum = 0;
      for (var j = 0; j < period; j++) sum += closes[j];
      out.add(sum / period);
      continue;
    }
    final prev = out[i - 1]!;
    out.add(alpha * closes[i] + (1 - alpha) * prev);
  }
  return out;
}

/// 成交量序列（与 candles 一一对应，无计算）
List<int> volumeSeries(List<int> volumes) => List<int>.from(volumes);

/// MACD 结果
class MacdResult {
  const MacdResult({
    required this.macdLine,
    required this.signalLine,
    required this.histogram,
  });
  final List<double?> macdLine;
  final List<double?> signalLine;
  final List<double?> histogram;
}

/// MACD（快线 12，慢线 26，信号线 9）
MacdResult macd(List<double> closes, {int fast = 12, int slow = 26, int signal = 9}) {
  if (closes.isEmpty || slow < fast) {
    return MacdResult(
      macdLine: [],
      signalLine: [],
      histogram: [],
    );
  }
  final fastEma = ema(closes, fast);
  final slowEma = ema(closes, slow);
  final n = closes.length;
  final macdLine = <double?>[];
  for (var i = 0; i < n; i++) {
    final f = fastEma[i];
    final s = slowEma[i];
    if (f == null || s == null) {
      macdLine.add(null);
    } else {
      macdLine.add(f - s);
    }
  }
  // signal = EMA(signal period) of macdLine（仅对非 null 的 macd 值做 EMA，再按索引填回）
  final signalEma = _emaOverNonNull(macdLine, signal);
  final histogram = <double?>[];
  for (var i = 0; i < n; i++) {
    final m = macdLine[i];
    final sig = signalEma[i];
    if (m == null || sig == null) {
      histogram.add(null);
    } else {
      histogram.add(m - sig);
    }
  }
  return MacdResult(macdLine: macdLine, signalLine: signalEma, histogram: histogram);
}

/// 对含 null 的序列做 EMA：只对非 null 值做 EMA，首 period 个有效值用 SMA 起算，结果按原索引填回
List<double?> _emaOverNonNull(List<double?> series, int period) {
  if (series.isEmpty) return [];
  final valid = <int, double>{};
  for (var i = 0; i < series.length; i++) {
    final v = series[i];
    if (v != null) valid[i] = v;
  }
  if (valid.isEmpty) return series.map((_) => null as double?).toList();
  final indices = valid.keys.toList()..sort();
  final values = indices.map((i) => valid[i]!).toList();
  final emaValues = _emaList(values, period);
  final out = List<double?>.filled(series.length, null);
  for (var k = 0; k < indices.length; k++) out[indices[k]] = emaValues[k];
  return out;
}

/// 对无 null 的序列做 EMA，前 period-1 个为 null，第 period 个为前 period 的 SMA，之后为 EMA
List<double?> _emaList(List<double> values, int period) {
  if (values.isEmpty || period < 1) return [];
  final out = <double?>[];
  final alpha = 2.0 / (period + 1);
  for (var i = 0; i < values.length; i++) {
    if (i < period - 1) {
      out.add(null);
      continue;
    }
    if (i == period - 1) {
      double sum = 0;
      for (var j = 0; j < period; j++) sum += values[j];
      out.add(sum / period);
      continue;
    }
    out.add(alpha * values[i] + (1 - alpha) * out[i - 1]!);
  }
  return out;
}

/// RSI（相对强弱指数，周期默认 14）
/// 返回值 0～100，前 period 个为 null
List<double?> rsi(List<double> closes, {int period = 14}) {
  if (closes.length < 2 || period < 2) return closes.map((_) => null as double?).toList();
  final out = <double?>[];
  for (var i = 0; i < period; i++) out.add(null);
  double avgGain = 0, avgLoss = 0;
  for (var i = 1; i <= period; i++) {
    final ch = closes[i] - closes[i - 1];
    if (ch > 0) avgGain += ch; else avgLoss -= ch;
  }
  avgGain /= period;
  avgLoss /= period;
  if (avgLoss == 0) {
    out.add(100.0);
  } else {
    final rs = avgGain / avgLoss;
    out.add(100 - 100 / (1 + rs));
  }
  for (var i = period + 1; i < closes.length; i++) {
    final ch = closes[i] - closes[i - 1];
    final gain = ch > 0 ? ch : 0.0;
    final loss = ch < 0 ? -ch : 0.0;
    avgGain = (avgGain * (period - 1) + gain) / period;
    avgLoss = (avgLoss * (period - 1) + loss) / period;
    if (avgLoss == 0) {
      out.add(100.0);
    } else {
      final rs = avgGain / avgLoss;
      out.add(100 - 100 / (1 + rs));
    }
  }
  return out;
}
