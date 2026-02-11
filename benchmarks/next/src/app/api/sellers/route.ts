import { NextResponse } from 'next/server';
import { db } from '@/lib/db';

export const dynamic = 'force-dynamic';

export async function GET() {
  const sellers = await db.getSellers();
  return NextResponse.json(sellers);
}
