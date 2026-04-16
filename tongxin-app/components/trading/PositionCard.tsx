import { memo, useState } from 'react';
import { View, Text, TouchableOpacity, TextInput, StyleSheet, Modal, ScrollView } from 'react-native';
import { useTranslation } from 'react-i18next';
import type { PositionResponse } from '../../services/api/tradingApi';
import { updateTPSL, partialClosePosition } from '../../services/api/tradingApi';
import { toDisplaySymbol } from '../../services/utils/symbolFormat';
import { showAlert } from '../../services/utils/dialog';

interface Props {
  position: PositionResponse;
  onClose: (id: string) => void;
  onUpdated?: () => void;
}

const fmt = (v: number | undefined | null, d = 2) =>
  v != null && isFinite(v) ? v.toFixed(d) : '--';

function PositionCard({ position, onClose, onUpdated }: Props) {
  const { t } = useTranslation();
  const baseAsset = position.symbol.includes('/') ? position.symbol.split('/')[0] : position.symbol;
  const isLong = position.side === 'long';
  const pnl = position.unrealized_pnl ?? 0;
  const roe = position.roe ?? 0;
  const pnlColor = pnl >= 0 ? '#0ECB81' : '#F6465D';
  const sideColor = isLong ? '#0ECB81' : '#F6465D';
  const sideLabel = isLong ? t('trading.longSide') : t('trading.shortSide');
  const roeStr = roe >= 0 ? `+${fmt(roe)}%` : `${fmt(roe)}%`;
  const pnlStr = pnl >= 0 ? `+${fmt(pnl)}` : fmt(pnl);

  // 已实现盈亏 breakdown
  const closingPnl = position.realized_pnl ?? 0;       // 平仓盈亏
  const fundingFee = 0;                                  // 资金费用 (not tracked yet)
  const tradingFee = -((position.open_fee ?? 0) + (position.close_fee ?? 0)); // 交易费用 (negative = cost)
  const totalRealizedPnl = closingPnl + fundingFee + tradingFee;
  const [showRealizedDetail, setShowRealizedDetail] = useState(false);

  // TP/SL modal
  const [showTPSL, setShowTPSL] = useState(false);
  const [tpInput, setTpInput] = useState(position.tp_price != null ? String(position.tp_price) : '');
  const [slInput, setSlInput] = useState(position.sl_price != null ? String(position.sl_price) : '');
  const [tpProfitInput, setTpProfitInput] = useState('');
  const [slLossInput, setSlLossInput] = useState('');
  const [tpMode, setTpMode] = useState<'pnl' | 'roi'>('pnl'); // Profit or ROI
  const [slMode, setSlMode] = useState<'pnl' | 'roi'>('pnl');
  const [showTpModeMenu, setShowTpModeMenu] = useState(false);
  const [showSlModeMenu, setShowSlModeMenu] = useState(false);
  const [tpslLoading, setTpslLoading] = useState(false);

  const entry = position.entry_price ?? 0;
  const qty = position.qty ?? 0;
  const lev = position.leverage ?? 1;

  // Price → Profit/ROI
  const calcProfitFromPrice = (price: number, mode: 'pnl' | 'roi') => {
    if (!price || !entry || !qty) return '';
    const diff = isLong ? price - entry : entry - price;
    if (mode === 'pnl') return (diff * qty).toFixed(2);
    return ((diff / entry) * lev * 100).toFixed(2);
  };

  // Profit/ROI → Price
  const calcPriceFromProfit = (val: number, mode: 'pnl' | 'roi') => {
    if (!entry || !qty) return '';
    if (mode === 'pnl') {
      const diff = val / qty;
      return (isLong ? entry + diff : entry - diff).toFixed(2);
    }
    // ROI: roi% = (diff / entry) * leverage * 100
    const diff = (val / 100) * entry / lev;
    return (isLong ? entry + diff : entry - diff).toFixed(2);
  };

  // Handle TP price change → update profit display
  const handleTpPriceChange = (v: string) => {
    setTpInput(v);
    const price = parseFloat(v);
    if (price && entry && qty) {
      setTpProfitInput(calcProfitFromPrice(price, tpMode));
    } else {
      setTpProfitInput('');
    }
  };

  // Handle TP profit change → update price
  const handleTpProfitChange = (v: string) => {
    setTpProfitInput(v);
    const val = parseFloat(v);
    if (val && entry && qty) {
      setTpInput(calcPriceFromProfit(val, tpMode));
    } else {
      setTpInput('');
    }
  };

  // Handle SL price change → update loss display
  const handleSlPriceChange = (v: string) => {
    setSlInput(v);
    const price = parseFloat(v);
    if (price && entry && qty) {
      const raw = calcProfitFromPrice(price, slMode);
      const num = parseFloat(raw);
      // 止损亏损自动显示为负数
      if (num > 0) {
        setSlLossInput('-' + raw);
      } else {
        setSlLossInput(raw);
      }
    } else {
      setSlLossInput('');
    }
  };

  // Handle SL loss change → update price
  const handleSlLossChange = (v: string) => {
    // 自动加负号：用户输入正数时自动转为负数
    let display = v;
    if (v && !v.startsWith('-') && v !== '0' && v !== '') {
      display = '-' + v;
    }
    setSlLossInput(display);
    const val = parseFloat(display);
    if (val && entry && qty) {
      // 传给calcPriceFromProfit的是负值，会正确计算止损价
      setSlInput(calcPriceFromProfit(val, slMode));
    } else {
      setSlInput('');
    }
  };

  // Switch TP mode → recalculate profit display from current price
  const switchTpMode = (mode: 'pnl' | 'roi') => {
    setTpMode(mode);
    setShowTpModeMenu(false);
    const price = parseFloat(tpInput);
    if (price && entry && qty) {
      setTpProfitInput(calcProfitFromPrice(price, mode));
    }
  };

  // Switch SL mode → recalculate loss display from current price
  const switchSlMode = (mode: 'pnl' | 'roi') => {
    setSlMode(mode);
    setShowSlModeMenu(false);
    const price = parseFloat(slInput);
    if (price && entry && qty) {
      const raw = calcProfitFromPrice(price, mode);
      const num = parseFloat(raw);
      setSlLossInput(num > 0 ? '-' + raw : raw);
    }
  };

  // Qty display mode
  const [qtyUsdt, setQtyUsdt] = useState(false);
  const [showQtyMenu, setShowQtyMenu] = useState(false);
  const notional = qty * entry;
  const qtyValue = qtyUsdt ? fmt(notional, 2) : String(position.qty ?? '--');
  const qtyUnit = qtyUsdt ? 'USDT' : baseAsset;

  // Partial close
  const [closeQtyInput, setCloseQtyInput] = useState(String(position.qty ?? ''));
  const [partialLoading, setPartialLoading] = useState(false);

  const handleSaveTPSL = async () => {
    setTpslLoading(true);
    try {
      const tp = tpInput ? parseFloat(tpInput) : undefined;
      const sl = slInput ? parseFloat(slInput) : undefined;
      await updateTPSL(position.id, tp, sl);
      setShowTPSL(false);
      onUpdated?.();
    } catch (e: any) {
      const msg = e?.response?.data?.error || e?.message || t('trading.setFailed');
      showAlert(msg, t('trading.setFailed'), 'danger');
    } finally {
      setTpslLoading(false);
    }
  };

  const handlePartialClose = async () => {
    const qty = parseFloat(closeQtyInput);
    if (!qty || qty <= 0) return;
    setPartialLoading(true);
    try {
      await partialClosePosition(position.id, qty);
      setCloseQtyInput('');
      onUpdated?.();
    } catch (e: any) {
      const msg = e?.response?.data?.error || e?.message || t('trading.closeFailed');
      showAlert(msg, t('trading.closeFailed'), 'danger');
    } finally {
      setPartialLoading(false);
    }
  };

  return (
    <View style={st.card}>
      {/* Header */}
      <View style={st.header}>
        <View style={st.headerLeft}>
          <View style={[st.sideBadge, { backgroundColor: sideColor }]}>
            <Text style={st.sideBadgeText}>{sideLabel}</Text>
          </View>
          <Text style={st.symbol}>{toDisplaySymbol(position.symbol)}</Text>
          {position.is_copy_trade && (
            <View style={st.copyBadge}>
              <Text style={st.copyBadgeText}>{t('trading.copyTrade')}</Text>
            </View>
          )}
          <View style={st.leverageBadge}>
            <Text style={st.leverageText}>{position.leverage ?? '--'}x</Text>
          </View>
          <Text style={st.marginModeText}>{position.margin_mode === 'cross' ? t('trading.crossModeFull') : t('trading.isolatedMode')}</Text>
        </View>
        <View style={{ alignItems: 'flex-end' }}>
          <Text style={[st.headerPnl, { color: pnlColor }]}>{pnlStr} USDT</Text>
          <Text style={[st.headerRoe, { color: pnlColor }]}>{roeStr}</Text>
        </View>
      </View>

      {/* Details grid */}
      <View style={st.detailGrid}>
        <View style={[st.detailCell, showQtyMenu && { zIndex: 20 }]}>
          <TouchableOpacity onPress={() => setShowQtyMenu(!showQtyMenu)} activeOpacity={0.7} style={{ flexDirection: 'row', alignItems: 'center' }}>
            <Text style={st.detailLabel}>{t('trading.quantity')}({qtyUnit})</Text>
            <Text style={st.toggleArrow}> ▾</Text>
          </TouchableOpacity>
          <Text style={st.detailValue}>{qtyValue}</Text>
          {showQtyMenu && (
            <View style={st.qtyMenu}>
              <TouchableOpacity style={[st.qtyMenuItem, !qtyUsdt && st.qtyMenuItemActive]} onPress={() => { setQtyUsdt(false); setShowQtyMenu(false); }} activeOpacity={0.7}>
                <Text style={st.qtyMenuItemText}>{t('trading.coinMode', { asset: baseAsset })}</Text>
              </TouchableOpacity>
              <TouchableOpacity style={[st.qtyMenuItem, qtyUsdt && st.qtyMenuItemActive]} onPress={() => { setQtyUsdt(true); setShowQtyMenu(false); }} activeOpacity={0.7}>
                <Text style={st.qtyMenuItemText}>USDT</Text>
              </TouchableOpacity>
            </View>
          )}
        </View>
        <DetailItem label={t('trading.margin')} value={fmt(position.margin_amount)} />
        <DetailItem label={t('trading.openAvgPrice')} value={fmt(position.entry_price)} />
        <DetailItem label={t('trading.markPrice')} value={fmt(position.current_price)} />
        <DetailItem label={t('trading.liqPrice')} value={position.liq_price ? fmt(position.liq_price) : '--'} />
        <TouchableOpacity style={st.detailCell} activeOpacity={0.7} onPress={() => {
          const tp = position.tp_price != null ? String(position.tp_price) : '';
          const sl = position.sl_price != null ? String(position.sl_price) : '';
          setTpInput(tp);
          setSlInput(sl);
          setTpProfitInput(tp && entry && qty ? calcProfitFromPrice(parseFloat(tp), tpMode) : '');
          const slRaw = sl && entry && qty ? calcProfitFromPrice(parseFloat(sl), slMode) : '';
          const slNum = parseFloat(slRaw);
          setSlLossInput(slRaw && slNum > 0 ? '-' + slRaw : slRaw);
          setShowTPSL(true);
        }}>
          <Text style={st.detailLabel}>TP/SL</Text>
          <Text style={[st.detailValue, { color: position.tp_price != null || position.sl_price != null ? '#C9A84C' : '#bbb', fontSize: 10 }]} numberOfLines={1}>
            {position.tp_price != null ? fmt(position.tp_price) : '--'} / {position.sl_price != null ? fmt(position.sl_price) : '--'}
          </Text>
        </TouchableOpacity>
        {/* 已实现盈亏 */}
        <View
          style={[st.detailCell, { position: 'relative', zIndex: showRealizedDetail ? 50 : 0 }]}
          // @ts-ignore web hover events
          onMouseEnter={() => setShowRealizedDetail(true)}
          onMouseLeave={() => setShowRealizedDetail(false)}
        >
          <Text style={[st.detailLabel, { textDecorationLine: 'underline', textDecorationStyle: 'dashed' }]}>{t('trading.realizedPnl')}</Text>
          <Text style={[st.detailValue, { color: totalRealizedPnl >= 0 ? '#0ECB81' : '#F6465D', fontWeight: '600' }]}>
            {totalRealizedPnl >= 0 ? '+' : ''}{fmt(totalRealizedPnl, 8)}
          </Text>
          {showRealizedDetail && (
            <View style={st.realizedTooltip}>
              <View style={st.realizedPopoverRow}>
                <Text style={st.realizedPopoverTitle}>{t('trading.realizedPnl')}</Text>
                <Text style={[st.realizedPopoverTitleVal, { color: totalRealizedPnl >= 0 ? '#0ECB81' : '#F6465D' }]}>
                  {fmt(totalRealizedPnl, 8)} USDT
                </Text>
              </View>
              <View style={st.realizedPopoverDivider} />
              <View style={st.realizedPopoverRow}>
                <Text style={st.realizedPopoverLabel}>{t('trading.closingPnl')}</Text>
                <Text style={st.realizedPopoverVal}>{fmt(closingPnl, 8)} USDT</Text>
              </View>
              <View style={st.realizedPopoverRow}>
                <Text style={st.realizedPopoverLabel}>{t('trading.fundingFee')}</Text>
                <Text style={st.realizedPopoverVal}>{fmt(fundingFee, 8)} USDT</Text>
              </View>
              <View style={st.realizedPopoverRow}>
                <Text style={st.realizedPopoverLabel}>{t('trading.tradingFee')}</Text>
                <Text style={[st.realizedPopoverVal, { color: tradingFee < 0 ? '#F6465D' : '#bbb' }]}>
                  {fmt(tradingFee, 8)} USDT
                </Text>
              </View>
              <View style={st.realizedPopoverDivider} />
              <Text style={st.realizedPopoverFormula}>{t('trading.realizedFormula')}</Text>
            </View>
          )}
        </View>
      </View>

      {/* Action row */}
      <View style={st.actions}>
        <View style={st.closeFieldGroup}>
          <Text style={st.closeFieldLabel}>{t('trading.price')}</Text>
          <Text style={st.closeFieldValue}>Market</Text>
        </View>
        <View style={st.closeFieldGroup}>
          <Text style={st.closeFieldLabel}>{t('trading.quantity')}</Text>
          <TextInput
            style={st.closeFieldInput}
            value={closeQtyInput}
            onChangeText={setCloseQtyInput}
            keyboardType="decimal-pad"
            placeholderTextColor="#555"
          />
        </View>
        <TouchableOpacity style={st.closeExecBtn} onPress={handlePartialClose} disabled={partialLoading} activeOpacity={0.7}>
          <Text style={st.closeExecBtnText}>{partialLoading ? '...' : t('trading.closePosition')}</Text>
        </TouchableOpacity>
        <TouchableOpacity style={st.actionBtn} onPress={() => onClose(position.id)} activeOpacity={0.7}>
          <Text style={st.actionBtnText}>{t('trading.marketCloseAll')}</Text>
        </TouchableOpacity>
        <TouchableOpacity style={[st.actionBtn, st.actionBtnHighlight]} onPress={() => {
          const tp = position.tp_price != null ? String(position.tp_price) : '';
          const sl = position.sl_price != null ? String(position.sl_price) : '';
          setTpInput(tp);
          setSlInput(sl);
          setTpProfitInput(tp && entry && qty ? calcProfitFromPrice(parseFloat(tp), tpMode) : '');
          const slRaw = sl && entry && qty ? calcProfitFromPrice(parseFloat(sl), slMode) : '';
          const slNum = parseFloat(slRaw);
          setSlLossInput(slRaw && slNum > 0 ? '-' + slRaw : slRaw);
          setShowTPSL(true);
        }} activeOpacity={0.7}>
          <Text style={st.actionBtnTextHighlight}>TP/SL</Text>
        </TouchableOpacity>
      </View>

      {/* ── TP/SL Modal ── */}
      {showTPSL && (
        <View style={st.modalOverlay}>
          <View style={st.modal}>
            {/* Modal Header */}
            <View style={st.modalHeader}>
              <Text style={st.modalTitle}>TP/SL</Text>
              <TouchableOpacity onPress={() => setShowTPSL(false)} activeOpacity={0.7}>
                <Text style={st.modalClose}>✕</Text>
              </TouchableOpacity>
            </View>

            <ScrollView style={{ maxHeight: 500 }} showsVerticalScrollIndicator={false}>
              {/* Position info bar */}
              <View style={st.posInfoBar}>
                <Text style={st.posInfoSymbol}>{toDisplaySymbol(position.symbol)}</Text>
                <View style={[st.posInfoBadge, { borderColor: sideColor }]}>
                  <Text style={[st.posInfoBadgeText, { color: sideColor }]}>{isLong ? 'Long' : 'Short'}</Text>
                </View>
                <View style={st.posInfoBadge}>
                  <Text style={st.posInfoBadgeText}>{position.margin_mode === 'cross' ? 'Cross' : 'Isolated'}</Text>
                </View>
                <View style={st.posInfoBadge}>
                  <Text style={st.posInfoBadgeText}>{position.leverage ?? '--'}X</Text>
                </View>
              </View>

              {/* Price info row */}
              <View style={st.priceInfoRow}>
                <View style={st.priceInfoItem}>
                  <Text style={st.priceInfoLabel}>Entry Price</Text>
                  <Text style={st.priceInfoValue}>{fmt(position.entry_price)}</Text>
                </View>
                <View style={st.priceInfoItem}>
                  <Text style={st.priceInfoLabel}>Latest price</Text>
                  <Text style={st.priceInfoValue}>{fmt(position.current_price)}</Text>
                </View>
                <View style={st.priceInfoItem}>
                  <Text style={st.priceInfoLabel}>Mark Price</Text>
                  <Text style={st.priceInfoValue}>{fmt(position.current_price)}</Text>
                </View>
                <View style={st.priceInfoItem}>
                  <Text style={st.priceInfoLabel}>Est. liq. price</Text>
                  <Text style={st.priceInfoValue}>{position.liq_price ? fmt(position.liq_price) : '--'}</Text>
                </View>
              </View>

              {/* TP & SL sections side by side */}
              <View style={st.tpslRow}>
                {/* TP Section */}
                <View style={[st.tpslSection, showTpModeMenu && { zIndex: 20 }]}>
                  <Text style={[st.tpslSectionTitle, { color: '#0ECB81' }]}>TP Trigger Setting</Text>
                  <Text style={st.tpslFieldLabel}>TP Trigger Price</Text>
                  <TextInput
                    style={st.tpslInput}
                    value={tpInput}
                    onChangeText={handleTpPriceChange}
                    placeholder={t('trading.triggerPrice')}
                    placeholderTextColor="#555"
                    keyboardType="decimal-pad"
                  />
                  <Text style={st.tpslFieldLabel}>Profit</Text>
                  <View style={st.profitInputRow}>
                    <TouchableOpacity style={st.profitModeBtn} onPress={() => { setShowTpModeMenu(!showTpModeMenu); setShowSlModeMenu(false); }} activeOpacity={0.7}>
                      <Text style={st.profitModeBtnText}>{tpMode === 'pnl' ? 'Profit' : 'ROI'} ▾</Text>
                    </TouchableOpacity>
                    <TextInput
                      style={st.profitInput}
                      value={tpProfitInput}
                      onChangeText={handleTpProfitChange}
                      placeholder="--"
                      placeholderTextColor="#555"
                      keyboardType="decimal-pad"
                    />
                    <Text style={st.profitUnit}>{tpMode === 'pnl' ? 'USDT' : '%'}</Text>
                  </View>
                  {showTpModeMenu && (
                    <View style={st.profitModeMenu}>
                      <TouchableOpacity style={[st.qtyMenuItem, tpMode === 'pnl' && st.qtyMenuItemActive]} onPress={() => switchTpMode('pnl')} activeOpacity={0.7}>
                        <Text style={st.qtyMenuItemText}>Profit</Text>
                      </TouchableOpacity>
                      <TouchableOpacity style={[st.qtyMenuItem, tpMode === 'roi' && st.qtyMenuItemActive]} onPress={() => switchTpMode('roi')} activeOpacity={0.7}>
                        <Text style={st.qtyMenuItemText}>ROI</Text>
                      </TouchableOpacity>
                    </View>
                  )}
                </View>

                {/* SL Section */}
                <View style={[st.tpslSection, showSlModeMenu && { zIndex: 20 }]}>
                  <Text style={[st.tpslSectionTitle, { color: '#F6465D' }]}>SL Trigger Setting</Text>
                  <Text style={st.tpslFieldLabel}>SL Trigger Price</Text>
                  <TextInput
                    style={st.tpslInput}
                    value={slInput}
                    onChangeText={handleSlPriceChange}
                    placeholder={t('trading.triggerPrice')}
                    placeholderTextColor="#555"
                    keyboardType="decimal-pad"
                  />
                  <Text style={st.tpslFieldLabel}>Loss Amount</Text>
                  <View style={st.profitInputRow}>
                    <TouchableOpacity style={st.profitModeBtn} onPress={() => { setShowSlModeMenu(!showSlModeMenu); setShowTpModeMenu(false); }} activeOpacity={0.7}>
                      <Text style={st.profitModeBtnText}>{slMode === 'pnl' ? 'Profit' : 'ROI'} ▾</Text>
                    </TouchableOpacity>
                    <TextInput
                      style={st.profitInput}
                      value={slLossInput}
                      onChangeText={handleSlLossChange}
                      placeholder="--"
                      placeholderTextColor="#555"
                      keyboardType="decimal-pad"
                    />
                    <Text style={st.profitUnit}>{slMode === 'pnl' ? 'USDT' : '%'}</Text>
                  </View>
                  {showSlModeMenu && (
                    <View style={st.profitModeMenu}>
                      <TouchableOpacity style={[st.qtyMenuItem, slMode === 'pnl' && st.qtyMenuItemActive]} onPress={() => switchSlMode('pnl')} activeOpacity={0.7}>
                        <Text style={st.qtyMenuItemText}>Profit</Text>
                      </TouchableOpacity>
                      <TouchableOpacity style={[st.qtyMenuItem, slMode === 'roi' && st.qtyMenuItemActive]} onPress={() => switchSlMode('roi')} activeOpacity={0.7}>
                        <Text style={st.qtyMenuItemText}>ROI</Text>
                      </TouchableOpacity>
                    </View>
                  )}
                </View>
              </View>

              {/* Summary */}
              {(tpInput || slInput) ? (
                <View style={st.summaryBox}>
                  {tpInput ? (
                    <Text style={st.summaryText}>
                      {t('trading.tpSummary', {
                        price: tpInput,
                        value: tpProfitInput || '--',
                        unit: ` ${tpMode === 'pnl' ? 'USDT' : '%'}`,
                      })}
                    </Text>
                  ) : null}
                  {slInput ? (
                    <Text style={st.summaryText}>
                      {t('trading.slSummary', {
                        price: slInput,
                        value: slLossInput || '--',
                        unit: ` ${slMode === 'pnl' ? 'USDT' : '%'}`,
                      })}
                    </Text>
                  ) : null}
                </View>
              ) : null}

              {/* Confirm button */}
              <TouchableOpacity style={st.confirmBtn} onPress={handleSaveTPSL} disabled={tpslLoading} activeOpacity={0.8}>
                <Text style={st.confirmBtnText}>{tpslLoading ? '...' : 'Confirm'}</Text>
              </TouchableOpacity>
            </ScrollView>
          </View>
        </View>
      )}

    </View>
  );
}

function DetailItem({ label, value, color }: { label: string; value: string; color?: string }) {
  return (
    <View style={st.detailCell}>
      <Text style={st.detailLabel}>{label}</Text>
      <Text style={[st.detailValue, color ? { color } : undefined]}>{value}</Text>
    </View>
  );
}

const st = StyleSheet.create({
  card: {
    backgroundColor: '#1A1A1A',
    borderRadius: 10,
    padding: 14,
    marginBottom: 8,
    marginHorizontal: 4,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.04)',
    overflow: 'visible',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    marginBottom: 12,
  },
  headerLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    flexShrink: 1,
  },
  sideBadge: { paddingHorizontal: 7, paddingVertical: 2, borderRadius: 4 },
  sideBadgeText: { color: '#fff', fontSize: 11, fontWeight: '700' },
  symbol: { color: '#fff', fontSize: 14, fontWeight: '700' },
  leverageBadge: { backgroundColor: 'rgba(201,168,76,0.18)', paddingHorizontal: 6, paddingVertical: 2, borderRadius: 4 },
  leverageText: { color: '#C9A84C', fontSize: 11, fontWeight: '600' },
  copyBadge: {
    backgroundColor: 'rgba(201, 168, 76, 0.18)',
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 4,
    borderWidth: 1,
    borderColor: 'rgba(201, 168, 76, 0.3)',
  },
  copyBadgeText: { color: '#C9A84C', fontSize: 10, fontWeight: '700' },
  marginModeText: { color: '#666', fontSize: 11 },
  headerPnl: { fontSize: 14, fontWeight: '700', fontFamily: 'monospace' },
  headerRoe: { fontSize: 12, fontWeight: '600', fontFamily: 'monospace', marginTop: 2 },
  detailGrid: { flexDirection: 'row', flexWrap: 'wrap', marginBottom: 12, overflow: 'visible' },
  detailCell: { width: '33.33%', marginBottom: 8, position: 'relative' },
  detailLabel: { color: '#555', fontSize: 11, marginBottom: 3 },
  toggleArrow: { color: '#888', fontSize: 10, marginBottom: 3 },
  qtyMenu: {
    position: 'absolute', top: '100%', left: 0,
    backgroundColor: '#2A2A2A', borderRadius: 6, borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.15)', zIndex: 50, elevation: 10,
    overflow: 'hidden', marginTop: 2, minWidth: 130,
  },
  qtyMenuItem: { paddingVertical: 7, paddingHorizontal: 10 },
  qtyMenuItemActive: { backgroundColor: 'rgba(201,168,76,0.15)' },
  qtyMenuItemText: { color: '#ccc', fontSize: 11 },
  detailValue: { color: '#bbb', fontSize: 12, fontFamily: 'monospace' },
  actions: {
    flexDirection: 'row', alignItems: 'flex-end', justifyContent: 'flex-start',
    gap: 10, borderTopWidth: 1, borderTopColor: 'rgba(255,255,255,0.05)',
    paddingTop: 10, flexWrap: 'wrap',
  },
  actionBtn: { backgroundColor: 'rgba(255,255,255,0.08)', paddingVertical: 5, paddingHorizontal: 10, borderRadius: 4 },
  actionBtnText: { color: '#ccc', fontSize: 11, fontWeight: '600' },
  actionBtnHighlight: { backgroundColor: 'rgba(201,168,76,0.15)' },
  actionBtnTextHighlight: { color: '#C9A84C', fontSize: 11, fontWeight: '600' },
  closeRow: {
    flexDirection: 'row', alignItems: 'flex-end', gap: 6,
    marginTop: 10, paddingTop: 10, borderTopWidth: 1, borderTopColor: 'rgba(255,255,255,0.05)',
  },
  closeFieldGroup: {},
  closeFieldLabel: { color: '#666', fontSize: 10, marginBottom: 2 },
  closeFieldValue: { color: '#888', fontSize: 12, fontFamily: 'monospace', paddingVertical: 5 },
  closeFieldInput: {
    backgroundColor: '#111', borderWidth: 1, borderColor: 'rgba(255,255,255,0.1)',
    borderRadius: 4, paddingHorizontal: 8, paddingVertical: 5,
    color: '#fff', fontSize: 12, fontFamily: 'monospace', width: 90,
  },
  closeExecBtn: {
    backgroundColor: '#F6465D', paddingVertical: 6, paddingHorizontal: 14,
    borderRadius: 4, alignItems: 'center', justifyContent: 'center',
  },
  closeExecBtnText: { color: '#fff', fontSize: 11, fontWeight: '700' },

  // ── Realized PNL Tooltip ──
  realizedTooltip: {
    position: 'absolute',
    bottom: '100%',
    left: 0,
    marginBottom: 6,
    backgroundColor: '#2A2A2A',
    borderRadius: 10,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.15)',
    padding: 14,
    minWidth: 280,
    // @ts-ignore web shadow
    boxShadow: '0 4px 20px rgba(0,0,0,0.5)',
    zIndex: 100,
    elevation: 20,
  },
  realizedPopoverRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 6,
  },
  realizedPopoverTitle: {
    color: '#fff',
    fontSize: 12,
    fontWeight: '700',
  },
  realizedPopoverTitleVal: {
    fontSize: 13,
    fontWeight: '700',
    fontFamily: 'monospace',
  },
  realizedPopoverDivider: {
    height: 1,
    backgroundColor: 'rgba(255,255,255,0.08)',
    marginVertical: 6,
  },
  realizedPopoverLabel: {
    color: '#888',
    fontSize: 11,
  },
  realizedPopoverVal: {
    color: '#bbb',
    fontSize: 11,
    fontFamily: 'monospace',
  },
  realizedPopoverFormula: {
    color: '#666',
    fontSize: 10,
    marginTop: 2,
  },

  // ── TP/SL Modal ──
  modalOverlay: {
    position: 'fixed' as any,
    top: 0, left: 0, right: 0, bottom: 0,
    backgroundColor: 'rgba(0,0,0,0.7)',
    justifyContent: 'center', alignItems: 'center',
    zIndex: 1000,
  },
  modal: {
    backgroundColor: '#1E1E1E',
    borderRadius: 12,
    padding: 20,
    width: '90%',
    maxWidth: 560,
  },
  modalHeader: {
    flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center',
    marginBottom: 16,
  },
  modalTitle: { color: '#fff', fontSize: 16, fontWeight: '700' },
  modalClose: { color: '#888', fontSize: 20, padding: 4 },

  // Position info
  posInfoBar: {
    flexDirection: 'row', alignItems: 'center', gap: 8,
    backgroundColor: '#2A2A2A', borderRadius: 8, padding: 12, marginBottom: 12,
  },
  posInfoSymbol: { color: '#fff', fontSize: 14, fontWeight: '700' },
  posInfoBadge: {
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.2)',
    borderRadius: 4, paddingHorizontal: 8, paddingVertical: 2,
  },
  posInfoBadgeText: { color: '#aaa', fontSize: 11, fontWeight: '600' },

  // Price info
  priceInfoRow: {
    flexDirection: 'row', flexWrap: 'wrap',
    backgroundColor: '#2A2A2A', borderRadius: 8, padding: 12, marginBottom: 16,
    gap: 4,
  },
  priceInfoItem: { width: '48%', marginBottom: 4 },
  priceInfoLabel: { color: '#666', fontSize: 10, marginBottom: 2 },
  priceInfoValue: { color: '#ddd', fontSize: 13, fontFamily: 'monospace', fontWeight: '600' },

  // TP/SL sections
  tpslRow: { flexDirection: 'row', gap: 20, marginBottom: 20 },
  tpslSection: { flex: 1, position: 'relative' },
  tpslSectionTitle: { fontSize: 13, fontWeight: '700', marginBottom: 10 },
  tpslFieldLabel: { color: '#888', fontSize: 11, marginBottom: 4, marginTop: 8 },
  tpslInput: {
    backgroundColor: '#111', borderWidth: 1, borderColor: 'rgba(255,255,255,0.1)',
    borderRadius: 6, paddingHorizontal: 12, paddingVertical: 10,
    color: '#fff', fontSize: 14, fontFamily: 'monospace',
  },
  profitInputRow: {
    backgroundColor: '#111', borderRadius: 6, borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)',
    flexDirection: 'row', alignItems: 'center', overflow: 'hidden',
  },
  profitModeBtn: {
    paddingHorizontal: 10, paddingVertical: 10,
    borderRightWidth: 1, borderRightColor: 'rgba(255,255,255,0.08)',
    flexShrink: 0,
  },
  profitModeBtnText: { color: '#999', fontSize: 11, fontWeight: '600' },
  profitInput: {
    flex: 1, paddingHorizontal: 10, paddingVertical: 10,
    color: '#fff', fontSize: 13, fontFamily: 'monospace',
    minWidth: 0,
  },
  profitUnit: { color: '#666', fontSize: 11, paddingHorizontal: 8, flexShrink: 0 },
  profitModeMenu: {
    backgroundColor: '#333', borderRadius: 6, borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.2)', zIndex: 50, elevation: 10,
    overflow: 'hidden', marginTop: 4, marginBottom: 4,
  },

  summaryBox: { marginBottom: 12 },
  summaryText: { color: '#888', fontSize: 11, lineHeight: 18 },

  // Confirm
  confirmBtn: {
    backgroundColor: '#fff', borderRadius: 8, paddingVertical: 14,
    alignItems: 'center', marginTop: 4,
  },
  confirmBtnText: { color: '#111', fontSize: 14, fontWeight: '700' },
});

export default memo(PositionCard);
