import Link from 'next/link';
import { db } from '@/lib/db';
import type { CardSearchParams } from '@/lib/types';

export const dynamic = 'force-dynamic';

export default async function SearchPage({
  searchParams,
}: {
  searchParams: Promise<{ [key: string]: string | undefined }>;
}) {
  const params = await searchParams;

  const searchConfig: CardSearchParams = {
    q: params.q || undefined,
    game: params.game || undefined,
    set: params.set || undefined,
    rarity: params.rarity || undefined,
    page: parseInt(params.page || '1'),
    limit: 24,
    sort: (params.sort as CardSearchParams['sort']) || undefined,
    order: (params.order as CardSearchParams['order']) || 'asc',
  };

  if (params.minPrice) searchConfig.minPrice = parseFloat(params.minPrice);
  if (params.maxPrice) searchConfig.maxPrice = parseFloat(params.maxPrice);

  const [results, games] = await Promise.all([
    db.searchCards(searchConfig),
    db.getGames(),
  ]);

  const buildUrl = (newParams: Record<string, string | undefined>) => {
    const merged = { ...params, ...newParams, page: '1' };
    const urlParams = new URLSearchParams();
    Object.entries(merged).forEach(([key, value]) => {
      if (value) urlParams.set(key, value);
    });
    return `/search?${urlParams.toString()}`;
  };

  return (
    <div>
      <h1 className="text-3xl font-bold mb-8">Search Cards</h1>

      <div className="grid grid-cols-1 lg:grid-cols-4 gap-8">
        {/* Filters Sidebar */}
        <div className="lg:col-span-1">
          <div className="bg-white rounded-lg shadow p-4 sticky top-4">
            <form action="/search" method="GET">
              <div className="mb-4">
                <label className="block text-sm font-semibold mb-2">Search</label>
                <input
                  type="text"
                  name="q"
                  defaultValue={params.q}
                  placeholder="Card name..."
                  className="w-full border rounded px-3 py-2"
                />
              </div>

              <div className="mb-4">
                <label className="block text-sm font-semibold mb-2">Game</label>
                <select
                  name="game"
                  defaultValue={params.game}
                  className="w-full border rounded px-3 py-2"
                >
                  <option value="">All Games</option>
                  {games.map((game) => (
                    <option key={game.id} value={game.slug}>
                      {game.name}
                    </option>
                  ))}
                </select>
              </div>

              <div className="mb-4">
                <label className="block text-sm font-semibold mb-2">Sort By</label>
                <select
                  name="sort"
                  defaultValue={params.sort}
                  className="w-full border rounded px-3 py-2"
                >
                  <option value="">Relevance</option>
                  <option value="name">Name</option>
                  <option value="price">Price</option>
                </select>
              </div>

              <button
                type="submit"
                className="w-full bg-blue-600 text-white rounded py-2 hover:bg-blue-700"
              >
                Apply Filters
              </button>
            </form>
          </div>
        </div>

        {/* Results */}
        <div className="lg:col-span-3">
          <div className="flex justify-between items-center mb-4">
            <p className="text-gray-600">
              {results.total.toLocaleString()} results
              {params.q && ` for "${params.q}"`}
            </p>
            <div className="flex gap-2">
              <Link
                href={buildUrl({ order: 'asc' })}
                className={`px-3 py-1 text-sm rounded ${
                  params.order !== 'desc' ? 'bg-blue-100 text-blue-700' : 'bg-gray-100'
                }`}
              >
                Asc
              </Link>
              <Link
                href={buildUrl({ order: 'desc' })}
                className={`px-3 py-1 text-sm rounded ${
                  params.order === 'desc' ? 'bg-blue-100 text-blue-700' : 'bg-gray-100'
                }`}
              >
                Desc
              </Link>
            </div>
          </div>

          {results.items.length === 0 ? (
            <div className="bg-white rounded-lg shadow p-8 text-center">
              <p className="text-gray-500">No cards found. Try adjusting your filters.</p>
            </div>
          ) : (
            <>
              <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
                {results.items.map((card) => (
                  <Link
                    key={card.id}
                    href={`/cards/${card.id}`}
                    className="bg-white rounded-lg shadow p-3 hover:shadow-md transition"
                  >
                    <div className="aspect-[3/4] bg-gray-100 rounded mb-2 flex items-center justify-center">
                      <span className="text-gray-400 text-xs">{card.number}</span>
                    </div>
                    <h3 className="font-semibold text-sm truncate">{card.name}</h3>
                    <p className="text-xs text-gray-500">{card.rarity}</p>
                    <p className="text-xs text-gray-400">{card.type}</p>
                  </Link>
                ))}
              </div>

              {/* Pagination */}
              {results.totalPages > 1 && (
                <div className="flex justify-center gap-2 mt-8">
                  {results.page > 1 && (
                    <Link
                      href={buildUrl({ page: String(results.page - 1) })}
                      className="px-4 py-2 bg-white border rounded hover:bg-gray-50"
                    >
                      Previous
                    </Link>
                  )}
                  <span className="px-4 py-2">
                    Page {results.page} of {results.totalPages}
                  </span>
                  {results.page < results.totalPages && (
                    <Link
                      href={buildUrl({ page: String(results.page + 1) })}
                      className="px-4 py-2 bg-white border rounded hover:bg-gray-50"
                    >
                      Next
                    </Link>
                  )}
                </div>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
}
