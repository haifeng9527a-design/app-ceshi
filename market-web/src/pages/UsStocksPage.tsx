import React, { useState, useMemo } from 'react';
import { Sidebar } from '../components/us-stocks/Sidebar';
import { TopNavbar } from '../components/us-stocks/TopNavbar';
import { SearchBar } from '../components/us-stocks/SearchBar';
import { StockTable } from '../components/us-stocks/StockTable';
import { StockDetailPanel } from '../components/us-stocks/StockDetailPanel';
import { UsIndexCard } from '../components/us-stocks/IndexCard';
import { stocksMock, indexMock } from '../constants/stocksMock';
import type { StockRowData } from '../types/stocks';

export default function UsStocksPage() {
  const [search, setSearch] = useState('');
  const [selected, setSelected] = useState<StockRowData | null>(stocksMock[0] ?? null);

  const filteredRows = useMemo(() => {
    if (!search.trim()) return stocksMock;
    const q = search.trim().toLowerCase();
    return stocksMock.filter(
      (r) => r.code.toLowerCase().includes(q) || r.name.toLowerCase().includes(q)
    );
  }, [search]);

  return (
    <div className="flex h-screen bg-[#0B0F14] text-white overflow-hidden" style={{ fontFamily: 'Inter, system-ui, sans-serif' }}>
      <Sidebar />
      <div className="flex flex-col flex-1 min-w-0">
        <TopNavbar />
        <SearchBar value={search} onChange={setSearch} />
        <div className="flex-1 flex min-h-0">
          <div className="flex flex-col flex-[0.7] min-w-0 border-r" style={{ borderColor: 'rgba(255,255,255,0.06)' }}>
            <div className="px-4 py-2 flex gap-2 border-b" style={{ borderColor: 'rgba(255,255,255,0.06)' }}>
              <button type="button" className="px-4 py-2 rounded-xl bg-amber-500/15 text-amber-400 text-sm font-medium">热门</button>
              <button type="button" className="px-4 py-2 rounded-xl text-white/6 hover:text-white text-sm">自选</button>
            </div>
            <StockTable rows={filteredRows} selectedId={selected?.id ?? null} onSelect={setSelected} />
          </div>
          <StockDetailPanel stock={selected} />
        </div>
        <footer className="shrink-0 p-4 border-t grid grid-cols-4 gap-4 bg-[#0B0F14]" style={{ borderColor: 'rgba(255,255,255,0.06)' }}>
          {indexMock.map((idx) => (
            <UsIndexCard key={idx.symbol} data={idx} />
          ))}
        </footer>
      </div>
    </div>
  );
}
