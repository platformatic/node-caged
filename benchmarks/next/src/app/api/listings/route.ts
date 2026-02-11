import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import type { ListingSearchParams, Condition } from '@/lib/types';

export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest) {
  const searchParams = request.nextUrl.searchParams;

  const params: ListingSearchParams = {
    cardId: searchParams.get('cardId') || undefined,
    sellerId: searchParams.get('sellerId') || undefined,
    condition: (searchParams.get('condition') as Condition) || undefined,
    page: parseInt(searchParams.get('page') || '1'),
    limit: parseInt(searchParams.get('limit') || '20'),
  };

  const minPrice = searchParams.get('minPrice');
  const maxPrice = searchParams.get('maxPrice');
  if (minPrice) params.minPrice = parseFloat(minPrice);
  if (maxPrice) params.maxPrice = parseFloat(maxPrice);

  const result = await db.getListings(params);
  return NextResponse.json(result);
}
