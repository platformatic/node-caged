import { NextResponse } from 'next/server';
import { db } from '@/lib/db';

export const dynamic = 'force-dynamic';

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const card = await db.getCardWithListings(id);

  if (!card) {
    return NextResponse.json({ error: 'Card not found' }, { status: 404 });
  }

  return NextResponse.json(card);
}
