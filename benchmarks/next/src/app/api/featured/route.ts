import { NextResponse } from 'next/server';
import { db } from '@/lib/db';

export const dynamic = 'force-dynamic';

export async function GET() {
  const [featured, trendingCards, newReleases, games] = await Promise.all([
    db.getFeatured(),
    db.getTrendingCards(12),
    db.getNewReleaseSets(5),
    db.getGames(),
  ]);

  return NextResponse.json({
    ...featured,
    trendingCardsData: trendingCards,
    newReleasesData: newReleases,
    popularGamesData: games,
  });
}
