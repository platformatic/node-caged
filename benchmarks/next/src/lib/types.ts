// Shared TypeScript types for e-commerce data models

export interface Game {
  id: string;
  name: string;
  slug: string;
  description: string;
  imageUrl: string;
  cardCount: number;
}

export interface CardSet {
  id: string;
  gameId: string;
  name: string;
  slug: string;
  releaseDate: string;
  totalCards: number;
  imageUrl: string;
}

export interface CardAttributes {
  hp?: number;
  types?: string[];
  artist?: string;
  attack?: string;
  defense?: string;
  level?: number;
  [key: string]: string | number | string[] | undefined;
}

export interface Card {
  id: string;
  setId: string;
  gameId: string;
  name: string;
  number: string;
  rarity: string;
  type: string;
  imageUrl: string;
  attributes: CardAttributes;
}

export type Condition = 'Near Mint' | 'Lightly Played' | 'Moderately Played' | 'Heavily Played' | 'Damaged';

export interface Seller {
  id: string;
  name: string;
  slug: string;
  rating: number;
  salesCount: number;
  location: string;
}

export interface Listing {
  id: string;
  cardId: string;
  sellerId: string;
  condition: Condition;
  price: number;
  quantity: number;
  language: string;
  isFoil: boolean;
}

export interface Banner {
  id: string;
  imageUrl: string;
  link: string;
  title: string;
}

export interface Featured {
  banners: Banner[];
  trendingCards: string[];
  newReleases: string[];
  popularGames: string[];
}

export interface CartItem {
  listingId: string;
  quantity: number;
  addedAt: string;
}

export interface Cart {
  items: CartItem[];
  updatedAt: string;
}

export interface PaginatedResponse<T> {
  items: T[];
  total: number;
  page: number;
  limit: number;
  totalPages: number;
}

// API Query Parameters
export interface CardSearchParams {
  game?: string;
  set?: string;
  rarity?: string;
  minPrice?: number;
  maxPrice?: number;
  q?: string;
  page?: number;
  limit?: number;
  sort?: 'price' | 'name' | 'date';
  order?: 'asc' | 'desc';
}

export interface ListingSearchParams {
  cardId?: string;
  sellerId?: string;
  condition?: Condition;
  minPrice?: number;
  maxPrice?: number;
  page?: number;
  limit?: number;
}

// Extended types for API responses
export interface CardWithListings extends Card {
  listings: Listing[];
  lowestPrice?: number;
  listingCount: number;
}

export interface GameWithSets extends Game {
  sets: CardSet[];
}

export interface SetWithCards extends CardSet {
  cards: Card[];
  game: Game;
  total: number;
  totalPages: number;
}

export interface SellerWithListings extends Seller {
  listings: Listing[];
  total: number;
  totalPages: number;
}

export interface ListingWithDetails extends Listing {
  card: Card;
  seller: Seller;
}

export interface CartItemWithDetails extends CartItem {
  listing: ListingWithDetails;
}

export interface CartWithDetails {
  items: CartItemWithDetails[];
  subtotal: number;
  itemCount: number;
  updatedAt: string;
}
