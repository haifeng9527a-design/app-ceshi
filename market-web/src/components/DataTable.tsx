import React from 'react';
import { Sparkline } from './Sparkline';
import { formatPrice, formatPercent, formatChange } from '@/utils/format';
import { colorByChange } from '@/utils/colors';
import { TrendingUp, TrendingDown } from 'lucide-react';
import type { MoverRow, WatchlistRow } from '@/constants/mock';

const cellMono = 'font-mono text-sm';

/** 自选表格列：代码/名称、最新价、涨跌幅 */
export function WatchlistTable({
  rows,
  onAdd,
  searchFilter,
}: {
  rows: WatchlistRow[];
  onAdd: () => void;
  searchFilter?: string;
}) {
  const filtered = searchFilter
    ? rows.filter(
        (r) =>
          r.symbol.toLowerCase().includes(searchFilter.toLowerCase()) ||
          (r.name && r.name.toLowerCase().includes(searchFilter.toLowerCase()))
      )
    : rows;
  return (
    <div className="flex flex-col min-h-0">
      <table className="w-full text-left border-collapse">
        <thead>
          <tr className="text-white/50 text-xs font-semibold uppercase tracking-wider">
            <th className="pb-2 pr-2">代码/名称</th>
            <th className="pb-2 pr-2 text-right">最新价</th>
            <th className="pb-2 text-right">涨跌幅</th>
          </tr>
        </thead>
        <tbody>
          {filtered.map((r) => {
            const color = colorByChange(r.changePercent);
            const isUp = r.changePercent >= 0;
            return (
              <tr
                key={r.symbol}
                className="border-t border-white/5 hover:bg-white/5 transition-colors"
              >
                <td className="py-2.5 pr-2">
                  <span className="text-white font-medium">{r.symbol}</span>
                </td>
                <td className={`py-2.5 pr-2 text-right ${cellMono} text-white`}>
                  {formatPrice(r.price)}
                </td>
                <td className={`py-2.5 text-right ${cellMono}`} style={{ color }}>
                  <span className="inline-flex items-center justify-end gap-0.5">
                    {isUp ? <TrendingUp className="w-3.5 h-3.5 shrink-0" /> : <TrendingDown className="w-3.5 h-3.5 shrink-0" />}
                    {formatPercent(r.changePercent)}
                  </span>
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
      <button
        type="button"
        onClick={onAdd}
        className="mt-3 w-full py-2 rounded-btn border border-white/10 text-white/70 text-sm hover:bg-white/5 hover:text-white transition-colors"
      >
        + 添加
      </button>
    </div>
  );
}

/** 涨跌榜表格：名称、最新价、涨跌幅、Sparkline */
export function MoversTable({ rows }: { rows: MoverRow[] }) {
  return (
    <div className="overflow-auto min-h-0">
      <table className="w-full text-left border-collapse min-w-[320px]">
        <thead>
          <tr className="text-white/50 text-xs font-semibold uppercase tracking-wider">
            <th className="pb-2 pr-2">名称</th>
            <th className="pb-2 pr-2 text-right">最新价</th>
            <th className="pb-2 pr-2 text-right">涨跌幅</th>
            <th className="pb-2 w-28">Sparkline</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => {
            const color = colorByChange(r.changePercent);
            const isUp = r.changePercent >= 0;
            return (
              <tr
                key={r.symbol}
                className="border-t border-white/5 hover:bg-white/5 transition-colors"
              >
                <td className="py-2.5 pr-2 font-medium text-white">{r.symbol}</td>
                <td className={`py-2.5 pr-2 text-right ${cellMono} text-white`}>
                  {formatPrice(r.price)}
                </td>
                <td className={`py-2.5 pr-2 text-right ${cellMono}`} style={{ color }}>
                  <span className="inline-flex items-center justify-end gap-0.5">
                    {isUp ? <TrendingUp className="w-3.5 h-3.5 shrink-0" /> : <TrendingDown className="w-3.5 h-3.5 shrink-0" />}
                    {formatChange(r.change)}
                  </span>
                </td>
                <td className="py-2">
                  {r.sparkline?.length ? (
                    <Sparkline data={r.sparkline} changePercent={r.changePercent} width={80} height={24} />
                  ) : null}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

/** 市场热度紧凑表：名称、最新价、涨跌幅 */
export function MarketHeatTable({ rows }: { rows: MoverRow[] }) {
  return (
    <div className="overflow-auto min-h-0">
      <table className="w-full text-left border-collapse">
        <thead>
          <tr className="text-white/50 text-xs font-semibold uppercase tracking-wider">
            <th className="pb-2 pr-2">名称</th>
            <th className="pb-2 pr-2 text-right">最新价</th>
            <th className="pb-2 text-right">涨跌幅</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => {
            const color = colorByChange(r.changePercent);
            const isUp = r.changePercent >= 0;
            return (
              <tr
                key={r.symbol}
                className="border-t border-white/5 hover:bg-white/5 transition-colors"
              >
                <td className="py-2 pr-2 font-medium text-white text-sm">{r.symbol}</td>
                <td className={`py-2 pr-2 text-right ${cellMono} text-white text-sm`}>
                  {formatPrice(r.price)}
                </td>
                <td className={`py-2 text-right ${cellMono} text-sm`} style={{ color }}>
                  <span className="inline-flex items-center justify-end gap-0.5">
                    {isUp ? <TrendingUp className="w-3 h-3 shrink-0" /> : <TrendingDown className="w-3 h-3 shrink-0" />}
                    {formatPercent(r.changePercent)}
                  </span>
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
