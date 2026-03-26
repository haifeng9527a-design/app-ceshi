import React from 'react';
import { StockRow } from './StockRow';
import type { StockRowData } from '../../types/stocks';

const COLS = ['序号', '代码', '名称', '涨跌幅', '最新价', '涨跌额', '成交量', '成交额', '市盈率TTM', '市净率', '股息率'];

export function StockTable({
  rows,
  selectedId,
  onSelect,
}: {
  rows: StockRowData[];
  selectedId: string | null;
  onSelect: (row: StockRowData) => void;
}) {
  return (
    <div className="flex-1 overflow-auto">
      <table className="w-full border-collapse">
        <thead className="sticky top-0 z-10 bg-[#111827]">
          <tr className="text-left text-xs font-semibold" style={{ color: 'rgba(255,255,255,0.6)' }}>
            <th className="py-3 px-3 w-12">序号</th>
            <th className="py-3 px-3">代码</th>
            <th className="py-3 px-3">名称</th>
            <th className="py-3 px-3">涨跌幅</th>
            <th className="py-3 px-3">最新价</th>
            <th className="py-3 px-3">涨跌额</th>
            <th className="py-3 px-3">成交量</th>
            <th className="py-3 px-3">成交额</th>
            <th className="py-3 px-3">市盈率TTM</th>
            <th className="py-3 px-3">市净率</th>
            <th className="py-3 px-3">股息率</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row, i) => (
            <StockRow
              key={row.id}
              data={row}
              index={i + 1}
              selected={selectedId === row.id}
              onSelect={() => onSelect(row)}
            />
          ))}
        </tbody>
      </table>
    </div>
  );
}
