import Link from 'next/link';
import { db } from '@/lib/db';

export const dynamic = 'force-dynamic';

export default async function HomePage() {
  const [games, trendingCards, newReleases] = await Promise.all([
    db.getGames(),
    db.getTrendingCards(8),
    db.getNewReleaseSets(4),
  ]);

  return (
    <div className="space-y-12">
      {/* Hero Section */}
      <section className="text-center py-12 bg-gradient-to-r from-blue-600 to-purple-600 rounded-xl text-white">
        <h1 className="text-4xl font-bold mb-4">Trading Card Marketplace</h1>
        <p className="text-xl opacity-90 mb-6">
          Buy and sell cards from your favorite games
        </p>
        <Link
          href="/search"
          className="inline-block bg-white text-blue-600 px-6 py-3 rounded-lg font-semibold hover:bg-gray-100 transition"
        >
          Start Shopping
        </Link>
      </section>

      {/* Games Section */}
      <section>
        <div className="flex justify-between items-center mb-6">
          <h2 className="text-2xl font-bold">Browse by Game</h2>
          <Link href="/games" className="text-blue-600 hover:underline">
            View All
          </Link>
        </div>
        <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-5 gap-4">
          {games.map((game) => (
            <Link
              key={game.id}
              href={`/games/${game.slug}`}
              className="bg-white rounded-lg shadow p-4 hover:shadow-md transition"
            >
              <div className="aspect-square bg-gray-100 rounded mb-3 flex items-center justify-center">
                <span className="text-3xl">{game.name.charAt(0)}</span>
              </div>
              <h3 className="font-semibold text-center">{game.name}</h3>
              <p className="text-sm text-gray-500 text-center">
                {game.cardCount.toLocaleString()} cards
              </p>
            </Link>
          ))}
        </div>
      </section>

      {/* Trending Cards Section */}
      <section>
        <div className="flex justify-between items-center mb-6">
          <h2 className="text-2xl font-bold">Trending Cards</h2>
          <Link href="/search?sort=trending" className="text-blue-600 hover:underline">
            View All
          </Link>
        </div>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          {trendingCards.map((card) => (
            <Link
              key={card.id}
              href={`/cards/${card.id}`}
              className="bg-white rounded-lg shadow p-4 hover:shadow-md transition"
            >
              <div className="aspect-[3/4] bg-gray-100 rounded mb-3 flex items-center justify-center">
                <span className="text-gray-400 text-sm">{card.number}</span>
              </div>
              <h3 className="font-semibold text-sm truncate">{card.name}</h3>
              <p className="text-xs text-gray-500">{card.rarity}</p>
            </Link>
          ))}
        </div>
      </section>

      {/* New Releases Section */}
      <section>
        <div className="flex justify-between items-center mb-6">
          <h2 className="text-2xl font-bold">New Releases</h2>
          <Link href="/games" className="text-blue-600 hover:underline">
            View All Sets
          </Link>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          {newReleases.map((set) => (
            <Link
              key={set.id}
              href={`/sets/${set.slug}`}
              className="bg-white rounded-lg shadow p-4 hover:shadow-md transition"
            >
              <div className="aspect-video bg-gray-100 rounded mb-3 flex items-center justify-center">
                <span className="text-gray-400">{set.name.substring(0, 2)}</span>
              </div>
              <h3 className="font-semibold">{set.name}</h3>
              <p className="text-sm text-gray-500">
                {set.totalCards} cards | {set.releaseDate}
              </p>
            </Link>
          ))}
        </div>
      </section>
    </div>
  );
}
