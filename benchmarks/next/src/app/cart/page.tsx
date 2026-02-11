import Link from 'next/link';

export const dynamic = 'force-dynamic';

export default function CartPage() {
  // Cart is stateless for benchmark purposes - just shows empty state
  // In a real app, this would use cookies/session to track cart items

  return (
    <div>
      <h1 className="text-3xl font-bold mb-8">Shopping Cart</h1>

      <div className="bg-white rounded-lg shadow p-8 text-center">
        <div className="text-gray-400 text-6xl mb-4">&#128722;</div>
        <h2 className="text-xl font-semibold mb-2">Your cart is empty</h2>
        <p className="text-gray-500 mb-6">
          Start browsing and add some cards to your cart!
        </p>
        <Link
          href="/search"
          className="inline-block bg-blue-600 text-white px-6 py-3 rounded-lg hover:bg-blue-700"
        >
          Browse Cards
        </Link>
      </div>

      <div className="mt-8 bg-gray-50 rounded-lg p-6">
        <h3 className="font-semibold mb-4">Cart Information</h3>
        <p className="text-sm text-gray-600">
          This is a benchmark application. Cart functionality is simplified for performance testing.
          In production, cart items would be persisted using session cookies or a database.
        </p>
      </div>
    </div>
  );
}
