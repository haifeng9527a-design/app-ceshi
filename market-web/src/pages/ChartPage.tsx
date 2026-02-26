import React, { useState, useMemo } from 'react';
import { TopBar } from '../components/chart/TopBar';
import { TimeframeBar, type TimeframeId } from '../components/chart/TimeframeBar';
import { IntradayChart } from '../components/chart/IntradayChart';
import { CandlesChart } from '../components/chart/CandlesChart';
import { IndicatorsPanel } from '../components/chart/IndicatorsPanel';
import { StatsBar } from '../components/chart/StatsBar';
import { getIntradayMock, getCandlesMock, getChartStatsMock } from '../constants/mockChart';

const CHART_HEIGHT = 560;
const INDICATORS_HEIGHT = 260;

function getSymbolFromUrl(): string {
  if (typeof window === 'undefined') return 'VIR';
  const params = new URLSearchParams(window.location.search);
  let fromHash: string | null = null;
  const h = window.location.hash;
  const q = h.indexOf('?');
  if (q !== -1) fromHash = new URLSearchParams(h.slice(q)).get('symbol');
  return params.get('symbol') ?? fromHash ?? 'VIR';
}

export default function ChartPage() {
  const [symbol, setSymbol] = useState(getSymbolFromUrl);
  React.useEffect(() => {
    const sync = () => setSymbol(getSymbolFromUrl());
    sync();
    window.addEventListener('hashchange', sync);
    return () => window.removeEventListener('hashchange', sync);
  }, []);
  const [tab, setTab] = useState<'intraday' | 'kline'>('intraday');
  const [timeframe, setTimeframe] = useState<TimeframeId>('5m');
  const [maType, setMaType] = useState<'MA' | 'EMA'>('MA');

  const stats = useMemo(() => getChartStatsMock(symbol), [symbol]);
  const intradayData = useMemo(
    () => getIntradayMock(symbol, timeframe),
    [symbol, timeframe]
  );
  const candlesData = useMemo(
    () => getCandlesMock(symbol, timeframe),
    [symbol, timeframe]
  );

  const handleBack = () => {
    if (typeof window !== 'undefined' && window.history.length > 1) window.history.back();
  };

  return (
    <div
      className="min-h-screen flex flex-col"
      style={{
        background: '#0B0F14',
        color: 'rgba(255,255,255,0.92)',
        fontFamily: 'Inter, system-ui, sans-serif',
      }}
    >
      <TopBar
        symbol={symbol}
        price={stats.close}
        change={stats.change}
        changePercent={stats.changePercent}
        activeTab={tab}
        onTabChange={setTab}
        onBack={handleBack}
      />

      <main className="flex-1 flex flex-col min-h-0">
        <div className="relative flex-1 flex flex-col min-h-0" style={{ minHeight: CHART_HEIGHT }}>
          {tab === 'intraday' ? (
            <IntradayChart
              data={intradayData}
              prevClose={stats.prevClose}
              height={CHART_HEIGHT}
              className="flex-1 min-h-[560px]"
            />
          ) : (
            <CandlesChart
              data={candlesData}
              height={CHART_HEIGHT}
              showMA={maType === 'MA'}
              className="flex-1 min-h-[560px]"
            />
          )}

          <div className="absolute bottom-4 left-1/2 -translate-x-1/2 z-10">
            <TimeframeBar value={timeframe} onChange={setTimeframe} />
          </div>
        </div>

        {tab === 'kline' && (
          <div className="shrink-0 px-4 pb-4" style={{ minHeight: INDICATORS_HEIGHT }}>
            <IndicatorsPanel maType={maType} onMaTypeChange={setMaType} />
          </div>
        )}

        <StatsBar
          stats={stats}
          symbol={symbol}
          price={stats.close}
          change={stats.change}
          changePercent={stats.changePercent}
        />
      </main>
    </div>
  );
}
