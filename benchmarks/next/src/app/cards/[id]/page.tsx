import Link from 'next/link';
import { notFound } from 'next/navigation';
import { db } from '@/lib/db';

export const dynamic = 'force-dynamic';

export default async function CardDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const card = await db.getCardWithListings(id);

  if (!card) {
    notFound();
  }

  const [set, game, sellers] = await Promise.all([
    db.getSetBySlug(card.setId.replace(`${card.gameId}-`, '').replace(/-set-\d+$/, '')),
    db.getGameBySlug(card.gameId),
    db.getSellers(),
  ]);

  const sellerMap = new Map(sellers.map((s) => [s.id, s]));

  return (
    <div>
      <div className="mb-6">
        <Link href="/search" className="text-blue-600 hover:underline">
          &larr; Back to Search
        </Link>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        {/* Card Image */}
        <div className="lg:col-span-1">
          <div className="bg-white rounded-lg shadow p-4">
            <div className="aspect-[3/4] bg-gray-100 rounded flex items-center justify-center">
              <span className="text-gray-400">{card.number}</span>
            </div>
          </div>
        </div>

        {/* Card Details */}
        <div className="lg:col-span-2">
          <div className="bg-white rounded-lg shadow p-6 mb-6">
            <h1 className="text-3xl font-bold mb-2">{card.name}</h1>
            <p className="text-gray-600 mb-4">
              {game?.name} | {set?.name || card.setId} | {card.number}
            </p>

            <div className="grid grid-cols-2 gap-4 mb-6">
              <div>
                <span className="text-sm text-gray-500">Rarity</span>
                <p className="font-semibold">{card.rarity}</p>
              </div>
              <div>
                <span className="text-sm text-gray-500">Type</span>
                <p className="font-semibold">{card.type}</p>
              </div>
              {card.attributes.artist && (
                <div>
                  <span className="text-sm text-gray-500">Artist</span>
                  <p className="font-semibold">{card.attributes.artist as string}</p>
                </div>
              )}
              {card.attributes.hp && (
                <div>
                  <span className="text-sm text-gray-500">HP</span>
                  <p className="font-semibold">{card.attributes.hp as number}</p>
                </div>
              )}
            </div>

            {card.lowestPrice && (
              <div className="border-t pt-4">
                <span className="text-sm text-gray-500">Starting from</span>
                <p className="text-2xl font-bold text-green-600">
                  ${card.lowestPrice.toFixed(2)}
                </p>
                <p className="text-sm text-gray-500">
                  {card.listingCount} listings available
                </p>
              </div>
            )}
          </div>

          {/* Listings Table */}
          <div className="bg-white rounded-lg shadow">
            <div className="p-4 border-b">
              <h2 className="text-xl font-bold">Available Listings</h2>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full">
                <thead className="bg-gray-50">
                  <tr>
                    <th className="px-4 py-3 text-left text-sm font-semibold">Seller</th>
                    <th className="px-4 py-3 text-left text-sm font-semibold">Condition</th>
                    <th className="px-4 py-3 text-left text-sm font-semibold">Language</th>
                    <th className="px-4 py-3 text-right text-sm font-semibold">Price</th>
                    <th className="px-4 py-3 text-right text-sm font-semibold">Qty</th>
                  </tr>
                </thead>
                <tbody className="divide-y">
                  {card.listings.slice(0, 20).map((listing) => {
                    const seller = sellerMap.get(listing.sellerId);
                    return (
                      <tr key={listing.id} className="hover:bg-gray-50">
                        <td className="px-4 py-3">
                          <Link
                            href={`/sellers/${seller?.slug}`}
                            className="text-blue-600 hover:underline"
                          >
                            {seller?.name || 'Unknown'}
                          </Link>
                          {seller && (
                            <span className="text-xs text-gray-500 ml-2">
                              ({seller.rating.toFixed(1)})
                            </span>
                          )}
                        </td>
                        <td className="px-4 py-3">
                          <span
                            className={`text-sm ${
                              listing.condition === 'Near Mint'
                                ? 'text-green-600'
                                : listing.condition === 'Lightly Played'
                                ? 'text-yellow-600'
                                : 'text-orange-600'
                            }`}
                          >
                            {listing.condition}
                          </span>
                          {listing.isFoil && (
                            <span className="ml-2 text-xs bg-purple-100 text-purple-700 px-1 rounded">
                              Foil
                            </span>
                          )}
                        </td>
                        <td className="px-4 py-3 text-sm">{listing.language}</td>
                        <td className="px-4 py-3 text-right font-semibold">
                          ${listing.price.toFixed(2)}
                        </td>
                        <td className="px-4 py-3 text-right text-sm">
                          {listing.quantity}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
            {card.listings.length > 20 && (
              <div className="p-4 border-t text-center text-sm text-gray-500">
                Showing 20 of {card.listings.length} listings
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
