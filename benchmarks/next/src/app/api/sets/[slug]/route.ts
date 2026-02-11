import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';

export const dynamic = 'force-dynamic';

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ slug: string }> }
) {
  const { slug } = await params;
  const searchParams = request.nextUrl.searchParams;
  const page = parseInt(searchParams.get('page') || '1');
  const limit = parseInt(searchParams.get('limit') || '20');

  const set = await db.getSetWithCards(slug, page, limit);

  if (!set) {
    return NextResponse.json({ error: 'Set not found' }, { status: 404 });
  }

  return NextResponse.json(set);
}
