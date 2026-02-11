import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';

export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest) {
  const searchParams = request.nextUrl.searchParams;
  const gameSlug = searchParams.get('game');

  let gameId: string | undefined;
  if (gameSlug) {
    const game = await db.getGameBySlug(gameSlug);
    gameId = game?.id;
  }

  const sets = await db.getSets(gameId);
  return NextResponse.json(sets);
}
