import Link from 'next/link';
import { db } from '@/lib/db';

export const dynamic = 'force-dynamic';

export default async function GamesPage() {
  const games = await db.getGames();

  return (
    <div>
      <h1 className="text-3xl font-bold mb-8">All Games</h1>
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {games.map((game) => (
          <Link
            key={game.id}
            href={`/games/${game.slug}`}
            className="bg-white rounded-lg shadow-md p-6 hover:shadow-lg transition"
          >
            <div className="aspect-video bg-gray-100 rounded mb-4 flex items-center justify-center">
              <span className="text-5xl font-bold text-gray-300">
                {game.name.charAt(0)}
              </span>
            </div>
            <h2 className="text-xl font-bold mb-2">{game.name}</h2>
            <p className="text-gray-600 mb-4">{game.description}</p>
            <p className="text-sm text-blue-600">
              {game.cardCount.toLocaleString()} cards available
            </p>
          </Link>
        ))}
      </div>
    </div>
  );
}
