import type { Metadata } from 'next';
import { Geist, Geist_Mono } from 'next/font/google';
import Link from 'next/link';
import './globals.css';

const geistSans = Geist({
  variable: '--font-geist-sans',
  subsets: ['latin'],
});

const geistMono = Geist_Mono({
  variable: '--font-geist-mono',
  subsets: ['latin'],
});

export const metadata: Metadata = {
  title: 'CardMarket - Trading Card Marketplace',
  description: 'Buy and sell trading cards from Pokemon, Magic, Yu-Gi-Oh and more',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className={`${geistSans.variable} ${geistMono.variable} antialiased min-h-screen bg-gray-50`}>
        <header className="bg-white shadow-sm border-b">
          <div className="max-w-7xl mx-auto px-4 py-4">
            <nav className="flex items-center justify-between">
              <Link href="/" className="text-2xl font-bold text-blue-600">
                CardMarket
              </Link>
              <div className="flex items-center gap-6">
                <Link href="/games" className="text-gray-600 hover:text-gray-900">
                  Games
                </Link>
                <Link href="/search" className="text-gray-600 hover:text-gray-900">
                  Search
                </Link>
                <Link href="/sellers" className="text-gray-600 hover:text-gray-900">
                  Sellers
                </Link>
                <Link href="/cart" className="text-gray-600 hover:text-gray-900">
                  Cart
                </Link>
              </div>
            </nav>
          </div>
        </header>
        <main className="max-w-7xl mx-auto px-4 py-8">
          {children}
        </main>
        <footer className="bg-white border-t mt-auto">
          <div className="max-w-7xl mx-auto px-4 py-6 text-center text-gray-500 text-sm">
            CardMarket - Trading Card Marketplace Benchmark
          </div>
        </footer>
      </body>
    </html>
  );
}
