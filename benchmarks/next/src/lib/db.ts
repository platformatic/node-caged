/**
 * JSON Database Layer with Configurable Delay
 *
 * Environment variables:
 * - DB_DELAY_MIN: Minimum delay in ms (default: 1)
 * - DB_DELAY_MAX: Maximum delay in ms (default: 5)
 * - DB_DELAY_ENABLED: Enable/disable delay (default: true)
 */

import * as fs from 'fs';
import * as path from 'path';
import type {
  Game,
  CardSet,
  Card,
  Seller,
  Listing,
  Featured,
  PaginatedResponse,
  CardWithListings,
  GameWithSets,
  SetWithCards,
  SellerWithListings,
  ListingWithDetails,
  CardSearchParams,
  ListingSearchParams,
} from './types';

interface SortOptions<T> {
  field: keyof T;
  order: 'asc' | 'desc';
}

interface PaginationOptions<T> {
  page?: number;
  limit?: number;
  filter?: Partial<T>;
  sort?: SortOptions<T>;
}

class JsonDatabase {
  private cache = new Map<string, unknown[]>();
  private dataDir: string;
  private delayMin: number;
  private delayMax: number;
  private delayEnabled: boolean;
  private initialized = false;

  constructor(dataDir?: string) {
    this.dataDir = dataDir || this.findDataDir();
    this.delayMin = parseInt(process.env.DB_DELAY_MIN || '1', 10);
    this.delayMax = parseInt(process.env.DB_DELAY_MAX || '5', 10);
    this.delayEnabled = process.env.DB_DELAY_ENABLED !== 'false';
  }

  private findDataDir(): string {
    // Try common locations
    const candidates = [
      path.join(process.cwd(), 'data'),
      path.join(process.cwd(), '..', 'data'),
      path.join(__dirname, '..', 'data'),
      path.join(__dirname, 'data'),
    ];

    for (const dir of candidates) {
      if (fs.existsSync(path.join(dir, 'games.json'))) {
        return dir;
      }
    }

    return path.join(process.cwd(), 'data');
  }

  private async delay(): Promise<void> {
    if (!this.delayEnabled) return;
    const ms = Math.floor(
      Math.random() * (this.delayMax - this.delayMin + 1) + this.delayMin
    );
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  private async loadCollection<T>(name: string): Promise<T[]> {
    if (this.cache.has(name)) {
      return this.cache.get(name) as T[];
    }

    const filePath = path.join(this.dataDir, `${name}.json`);
    if (!fs.existsSync(filePath)) {
      console.warn(`Data file not found: ${filePath}`);
      return [];
    }

    try {
      const content = await fs.promises.readFile(filePath, 'utf-8');
      const data = JSON.parse(content);
      this.cache.set(name, data);
      return data as T[];
    } catch (err) {
      console.error(`Error loading ${name}.json:`, err);
      return [];
    }
  }

  private applyFilter<T>(data: T[], filter: Partial<T>): T[] {
    return data.filter((item) => {
      for (const [key, value] of Object.entries(filter)) {
        if (value === undefined || value === null) continue;
        const itemValue = (item as Record<string, unknown>)[key];
        if (itemValue !== value) return false;
      }
      return true;
    });
  }

  private applySort<T>(data: T[], sort: SortOptions<T>): T[] {
    return [...data].sort((a, b) => {
      const aVal = a[sort.field];
      const bVal = b[sort.field];

      if (aVal === bVal) return 0;
      if (aVal === null || aVal === undefined) return 1;
      if (bVal === null || bVal === undefined) return -1;

      const comparison = aVal < bVal ? -1 : 1;
      return sort.order === 'asc' ? comparison : -comparison;
    });
  }

  private applyTextSearch<T>(data: T[], query: string, fields: (keyof T)[]): T[] {
    const lowerQuery = query.toLowerCase();
    return data.filter((item) => {
      return fields.some((field) => {
        const value = item[field];
        if (typeof value === 'string') {
          return value.toLowerCase().includes(lowerQuery);
        }
        return false;
      });
    });
  }

  // Initialize (preload all data)
  async initialize(): Promise<void> {
    if (this.initialized) return;
    await this.loadCollection<Game>('games');
    await this.loadCollection<CardSet>('sets');
    await this.loadCollection<Card>('cards');
    await this.loadCollection<Seller>('sellers');
    await this.loadCollection<Listing>('listings');
    await this.loadCollection<Featured>('featured');
    this.initialized = true;
  }

  // Generic query methods
  async query<T>(collection: string, filter?: Partial<T>): Promise<T[]> {
    await this.delay();
    const data = await this.loadCollection<T>(collection);
    return filter ? this.applyFilter(data, filter) : data;
  }

  async findById<T extends { id: string }>(
    collection: string,
    id: string
  ): Promise<T | undefined> {
    await this.delay();
    const data = await this.loadCollection<T>(collection);
    return data.find((item) => item.id === id);
  }

  async findBySlug<T extends { slug: string }>(
    collection: string,
    slug: string
  ): Promise<T | undefined> {
    await this.delay();
    const data = await this.loadCollection<T>(collection);
    return data.find((item) => item.slug === slug);
  }

  async findMany<T extends { id: string }>(
    collection: string,
    ids: string[]
  ): Promise<T[]> {
    await this.delay();
    const data = await this.loadCollection<T>(collection);
    const idSet = new Set(ids);
    return data.filter((item) => idSet.has(item.id));
  }

  async paginate<T>(
    collection: string,
    options: PaginationOptions<T> = {}
  ): Promise<PaginatedResponse<T>> {
    await this.delay();
    const { page = 1, limit = 20, filter, sort } = options;
    let data = await this.loadCollection<T>(collection);

    if (filter) {
      data = this.applyFilter(data, filter);
    }

    if (sort) {
      data = this.applySort(data, sort);
    }

    const total = data.length;
    const start = (page - 1) * limit;
    const items = data.slice(start, start + limit);

    return {
      items,
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit),
    };
  }

  // Domain-specific methods
  async getGames(): Promise<Game[]> {
    return this.query<Game>('games');
  }

  async getGameBySlug(slug: string): Promise<Game | undefined> {
    return this.findBySlug<Game>('games', slug);
  }

  async getGameWithSets(slug: string): Promise<GameWithSets | undefined> {
    await this.delay();
    const game = await this.getGameBySlug(slug);
    if (!game) return undefined;

    const allSets = await this.loadCollection<CardSet>('sets');
    const sets = allSets.filter((s) => s.gameId === game.id);

    return { ...game, sets };
  }

  async getSets(gameId?: string): Promise<CardSet[]> {
    const filter = gameId ? { gameId } : undefined;
    return this.query<CardSet>('sets', filter as Partial<CardSet>);
  }

  async getSetBySlug(slug: string): Promise<CardSet | undefined> {
    return this.findBySlug<CardSet>('sets', slug);
  }

  async getSetWithCards(
    slug: string,
    page = 1,
    limit = 20
  ): Promise<SetWithCards | undefined> {
    await this.delay();
    const set = await this.getSetBySlug(slug);
    if (!set) return undefined;

    const games = await this.loadCollection<Game>('games');
    const game = games.find((g) => g.id === set.gameId);
    if (!game) return undefined;

    const allCards = await this.loadCollection<Card>('cards');
    const setCards = allCards.filter((c) => c.setId === set.id);
    const total = setCards.length;
    const start = (page - 1) * limit;
    const cards = setCards.slice(start, start + limit);

    return { ...set, cards, game, total, totalPages: Math.ceil(total / limit) };
  }

  async searchCards(params: CardSearchParams): Promise<PaginatedResponse<Card>> {
    await this.delay();
    const { game, set, rarity, q, page = 1, limit = 20, sort, order = 'asc' } = params;

    let cards = await this.loadCollection<Card>('cards');

    // Apply filters
    if (game) {
      const games = await this.loadCollection<Game>('games');
      const gameObj = games.find((g) => g.slug === game);
      if (gameObj) {
        cards = cards.filter((c) => c.gameId === gameObj.id);
      }
    }

    if (set) {
      const sets = await this.loadCollection<CardSet>('sets');
      const setObj = sets.find((s) => s.slug === set);
      if (setObj) {
        cards = cards.filter((c) => c.setId === setObj.id);
      }
    }

    if (rarity) {
      cards = cards.filter((c) => c.rarity === rarity);
    }

    if (q) {
      cards = this.applyTextSearch(cards, q, ['name', 'type', 'rarity']);
    }

    // Apply price filters if needed (requires joining with listings)
    if (params.minPrice !== undefined || params.maxPrice !== undefined) {
      const listings = await this.loadCollection<Listing>('listings');
      const cardPrices = new Map<string, number>();

      for (const listing of listings) {
        const existing = cardPrices.get(listing.cardId);
        if (existing === undefined || listing.price < existing) {
          cardPrices.set(listing.cardId, listing.price);
        }
      }

      cards = cards.filter((card) => {
        const price = cardPrices.get(card.id);
        if (price === undefined) return false;
        if (params.minPrice !== undefined && price < params.minPrice) return false;
        if (params.maxPrice !== undefined && price > params.maxPrice) return false;
        return true;
      });
    }

    // Apply sorting
    if (sort === 'name') {
      cards = this.applySort(cards, { field: 'name', order });
    } else if (sort === 'price') {
      // Sort by lowest listing price
      const listings = await this.loadCollection<Listing>('listings');
      const cardPrices = new Map<string, number>();
      for (const listing of listings) {
        const existing = cardPrices.get(listing.cardId);
        if (existing === undefined || listing.price < existing) {
          cardPrices.set(listing.cardId, listing.price);
        }
      }
      cards = [...cards].sort((a, b) => {
        const priceA = cardPrices.get(a.id) ?? Infinity;
        const priceB = cardPrices.get(b.id) ?? Infinity;
        return order === 'asc' ? priceA - priceB : priceB - priceA;
      });
    }

    const total = cards.length;
    const start = (page - 1) * limit;
    const items = cards.slice(start, start + limit);

    return {
      items,
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit),
    };
  }

  async getCardById(id: string): Promise<Card | undefined> {
    return this.findById<Card>('cards', id);
  }

  async getCardWithListings(id: string): Promise<CardWithListings | undefined> {
    await this.delay();
    const card = await this.getCardById(id);
    if (!card) return undefined;

    const allListings = await this.loadCollection<Listing>('listings');
    const listings = allListings.filter((l) => l.cardId === id);

    const lowestPrice = listings.length > 0
      ? Math.min(...listings.map((l) => l.price))
      : undefined;

    return {
      ...card,
      listings,
      lowestPrice,
      listingCount: listings.length,
    };
  }

  async getListings(params: ListingSearchParams): Promise<PaginatedResponse<Listing>> {
    await this.delay();
    const { cardId, sellerId, condition, minPrice, maxPrice, page = 1, limit = 20 } = params;

    let listings = await this.loadCollection<Listing>('listings');

    if (cardId) {
      listings = listings.filter((l) => l.cardId === cardId);
    }

    if (sellerId) {
      listings = listings.filter((l) => l.sellerId === sellerId);
    }

    if (condition) {
      listings = listings.filter((l) => l.condition === condition);
    }

    if (minPrice !== undefined) {
      listings = listings.filter((l) => l.price >= minPrice);
    }

    if (maxPrice !== undefined) {
      listings = listings.filter((l) => l.price <= maxPrice);
    }

    // Sort by price ascending by default
    listings = this.applySort(listings, { field: 'price', order: 'asc' });

    const total = listings.length;
    const start = (page - 1) * limit;
    const items = listings.slice(start, start + limit);

    return {
      items,
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit),
    };
  }

  async getListingById(id: string): Promise<Listing | undefined> {
    return this.findById<Listing>('listings', id);
  }

  async getListingWithDetails(id: string): Promise<ListingWithDetails | undefined> {
    await this.delay();
    const listing = await this.getListingById(id);
    if (!listing) return undefined;

    const cards = await this.loadCollection<Card>('cards');
    const sellers = await this.loadCollection<Seller>('sellers');
    const card = cards.find((c) => c.id === listing.cardId);
    const seller = sellers.find((s) => s.id === listing.sellerId);

    if (!card || !seller) return undefined;

    return { ...listing, card, seller };
  }

  async getSellers(): Promise<Seller[]> {
    return this.query<Seller>('sellers');
  }

  async getSellerBySlug(slug: string): Promise<Seller | undefined> {
    return this.findBySlug<Seller>('sellers', slug);
  }

  async getSellerWithListings(
    slug: string,
    page = 1,
    limit = 20
  ): Promise<SellerWithListings | undefined> {
    await this.delay();
    const seller = await this.getSellerBySlug(slug);
    if (!seller) return undefined;

    const allListings = await this.loadCollection<Listing>('listings');
    const sellerListings = allListings.filter((l) => l.sellerId === seller.id);
    const total = sellerListings.length;
    const start = (page - 1) * limit;
    const listings = sellerListings.slice(start, start + limit);

    return { ...seller, listings, total, totalPages: Math.ceil(total / limit) };
  }

  async getFeatured(): Promise<Featured | null> {
    await this.delay();
    const data = await this.loadCollection<Featured>('featured');
    // Featured is stored as an array with one item or as the object directly
    if (Array.isArray(data)) {
      return data[0] || null;
    }
    return data as unknown as Featured;
  }

  // Special method for featured that loads the file differently
  async getFeaturedContent(): Promise<Featured | null> {
    await this.delay();
    const filePath = path.join(this.dataDir, 'featured.json');
    if (!fs.existsSync(filePath)) {
      return null;
    }
    try {
      const content = await fs.promises.readFile(filePath, 'utf-8');
      const data = JSON.parse(content);
      return data as Featured;
    } catch {
      return null;
    }
  }

  async getTrendingCards(limit = 10): Promise<Card[]> {
    await this.delay();
    const featured = await this.getFeatured();
    if (!featured) return [];

    const trendingIds = featured.trendingCards.slice(0, limit);
    const cards = await this.loadCollection<Card>('cards');
    return cards.filter((c) => trendingIds.includes(c.id));
  }

  async getNewReleaseSets(limit = 5): Promise<CardSet[]> {
    await this.delay();
    const featured = await this.getFeatured();
    if (!featured) return [];

    const releaseIds = featured.newReleases.slice(0, limit);
    const sets = await this.loadCollection<CardSet>('sets');
    return sets.filter((s) => releaseIds.includes(s.id));
  }
}

// Export singleton instance
export const db = new JsonDatabase();

// Export class for custom instances
export { JsonDatabase };
