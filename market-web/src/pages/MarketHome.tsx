import React, { useState } from 'react';
import { LayoutGrid, MoreHorizontal, Plus } from 'lucide-react';
import { NavBar } from '@/components/NavBar';
import { IndexCard } from '@/components/IndexCard';
import { Panel } from '@/components/Panel';
import { Tabs } from '@/components/Tabs';
import { WatchlistTable, MoversTable, MarketHeatTable } from '@/components/DataTable';
import { Heatmap } from '@/components/Heatmap';
import {
  indexQuotes,
  watchlistRows,
  moversGainers,
  moversLosers,
  marketHeatGainers,
  marketHeatLosers,
  heatmapItems,
  trendingStocks,
  trendingCrypto,
} from '@/constants/mock';
import { formatPrice, formatPercent } from '@/utils/format';
import { colorByChange } from '@/utils/colors';
import { TrendingUp, TrendingDown } from 'lucide-react';
import type { TrendingRow } from '@/constants/mock';

const moversTabs = [{ key: 'gainers', label: '涨幅榜' }, { key: 'losers', label: '跌幅榜' }];
const heatTabs = [{ key: 'gainers', label: '涨幅榜' }, { key: 'losers', label: '跌幅榜' }];
const trendingTabs = [{ key: 'stocks', label: 'Stocks' }, { key: 'crypto', label: 'Crypto' }];

function TrendingList({ rows }: { rows: TrendingRow[] }) {
  const cellMono = 'font-mono text-sm';
  return (
    <div className="space-y-0">
      {rows.map((r) => {
        const color = colorByChange(r.changePercent);
        const isUp = r.changePercent >= 0;
        return (
          <div
            key={r.symbol}
            className="flex items-center justify-between py-2.5 border-t border-white/5 hover:bg-white/5 transition-colors px-1 -mx-1"
          >
            <span className="font-medium text-white">{r.symbol}</span>
            <div className="flex items-center gap-3">
              <span className={`${cellMono} text-white`}>{formatPrice(r.price)}</span>
              <span className={`${cellMono} flex items-center`} style={{ color }}>
                {isUp ? <TrendingUp className="w-3.5 h-3.5 mr-0.5" /> : <TrendingDown className="w-3.5 h-3.5 mr-0.5" />}
                {formatPercent(r.changePercent)}
              </span>
            </div>
          </div>
        );
      })}
    </div>
  );
}

export default function MarketHome() {
  const [mainTab, setMainTab] = useState('market');
  const [searchValue, setSearchValue] = useState('');
  const [moversTab, setMoversTab] = useState('gainers');
  const [heatTab, setHeatTab] = useState('gainers');
  const [trendingTab, setTrendingTab] = useState('stocks');

  const moversRows = moversTab === 'gainers' ? moversGainers : moversLosers;
  const heatRows = heatTab === 'gainers' ? marketHeatGainers : marketHeatLosers;
  const trendingRows = trendingTab === 'stocks' ? trendingStocks : trendingCrypto;

  return (
    <div className="min-h-screen flex flex-col bg-surface text-white">
      <NavBar
        activeTab={mainTab}
        onTabChange={setMainTab}
        searchValue={searchValue}
        onSearchChange={setSearchValue}
      />

      <main
        className="flex-1 overflow-auto px-7 md:px-9 py-6"
        style={{ paddingLeft: '28px', paddingRight: '36px', paddingTop: '24px', paddingBottom: '24px' }}
      >
        {/* 指数卡片区 */}
        <section className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4 xl:gap-5 mb-6">
          {indexQuotes.map((q) => (
            <IndexCard key={q.ticker} data={q} />
          ))}
        </section>

        {/* 主内容上半区：三列 -> 两列 -> 一列 */}
        <section className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4 xl:gap-5 mb-6">
          <Panel
            title="自选"
            right={
              <div className="flex items-center gap-1">
                <button type="button" className="p-1.5 rounded-btn text-white/6 hover:bg-white/5" aria-label="添加">
                  <Plus className="w-4 h-4" style={{ color: 'rgba(255,255,255,0.6)' }} />
                </button>
                <button type="button" className="p-1.5 rounded-btn text-white/6 hover:bg-white/5" aria-label="筛选">
                  <LayoutGrid className="w-4 h-4" style={{ color: 'rgba(255,255,255,0.6)' }} />
                </button>
              </div>
            }
          >
            <WatchlistTable
              rows={watchlistRows}
              onAdd={() => {}}
              searchFilter={searchValue || undefined}
            />
          </Panel>

          <Panel
            title="涨跌榜"
            right={
              <div className="flex items-center gap-2">
                <Tabs items={moversTabs} activeKey={moversTab} onChange={setMoversTab} />
                <a href="#" className="text-sm text-up hover:underline">更多 &gt;</a>
              </div>
            }
          >
            <MoversTable rows={moversRows} />
          </Panel>

          <Panel
            title="市场热度"
            right={
              <div className="flex items-center gap-2">
                <Tabs items={heatTabs} activeKey={heatTab} onChange={setHeatTab} />
                <a href="#" className="text-sm text-up hover:underline">更多 &gt;</a>
              </div>
            }
          >
            <MarketHeatTable rows={heatRows} />
          </Panel>
        </section>

        {/* 主内容下半区：两列 -> 一列 */}
        <section className="grid grid-cols-1 xl:grid-cols-2 gap-4 xl:gap-5">
          <Panel
            title="市场热度 Heatmap"
            right={
              <div className="flex items-center gap-2 text-sm text-white/6">
                <select
                  className="bg-transparent border border-white/10 rounded-btn py-1 px-2 text-white/8 focus:outline-none"
                  defaultValue="sp500"
                >
                  <option value="sp500">S&P 500</option>
                </select>
                <span>交易子类 &gt;</span>
              </div>
            }
          >
            <Heatmap items={heatmapItems} />
          </Panel>

          <Panel
            title="热门"
            right={
              <button type="button" className="p-1.5 rounded-btn text-white/6 hover:bg-white/5" aria-label="筛选">
                <MoreHorizontal className="w-4 h-4" style={{ color: 'rgba(255,255,255,0.6)' }} />
              </button>
            }
          >
            <Tabs items={trendingTabs} activeKey={trendingTab} onChange={setTrendingTab} className="mb-3" />
            <TrendingList rows={trendingRows} />
          </Panel>
        </section>
      </main>
    </div>
  );
}
