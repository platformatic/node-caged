import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import type { CardSearchParams } from '@/lib/types';

export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest) {
  const searchParams = request.nextUrl.searchParams;

  const params: CardSearchParams = {
    game: searchParams.get('game') || undefined,
    set: searchParams.get('set') || undefined,
    rarity: searchParams.get('rarity') || undefined,
    q: searchParams.get('q') || undefined,
    page: parseInt(searchParams.get('page') || '1'),
    limit: parseInt(searchParams.get('limit') || '20'),
    sort: (searchParams.get('sort') as CardSearchParams['sort']) || undefined,
    order: (searchParams.get('order') as CardSearchParams['order']) || 'asc',
  };

  const minPrice = searchParams.get('minPrice');
  const maxPrice = searchParams.get('maxPrice');
  if (minPrice) params.minPrice = parseFloat(minPrice);
  if (maxPrice) params.maxPrice = parseFloat(maxPrice);

  const result = await db.searchCards(params);
  return NextResponse.json(result);
}
