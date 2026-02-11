import { NextResponse } from 'next/server';
import { db } from '@/lib/db';

export const dynamic = 'force-dynamic';

export async function GET() {
  const games = await db.getGames();
  return NextResponse.json(games);
}
