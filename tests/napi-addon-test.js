/**
 * Test N-API based native addons with pointer compression
 *
 * Tests popular N-API addons to ensure they work correctly
 * when V8 pointer compression is enabled.
 *
 * NOTE: Only tests true N-API addons. Non-N-API native addons
 * (like better-sqlite3) may crash with pointer compression.
 */

const tests = [];
let passed = 0;
let failed = 0;

function test(name, fn) {
  tests.push({ name, fn });
}

async function runTests() {
  console.log('=== N-API Addon Compatibility Test ===\n');
  console.log(`Node.js: ${process.version}`);
  console.log(`Architecture: ${process.arch}`);
  console.log(`Platform: ${process.platform}\n`);

  for (const { name, fn } of tests) {
    process.stdout.write(`Testing ${name}... `);
    try {
      await fn();
      console.log('✓ PASS');
      passed++;
    } catch (err) {
      console.log(`✗ FAIL: ${err.message}`);
      failed++;
    }
  }

  console.log(`\n=== Results: ${passed} passed, ${failed} failed ===`);
  process.exit(failed > 0 ? 1 : 0);
}

// Test 1: bcrypt (N-API password hashing)
test('bcrypt (password hashing)', async () => {
  const bcrypt = require('bcrypt');
  const hash = await bcrypt.hash('test-password', 10);
  const match = await bcrypt.compare('test-password', hash);
  if (!match) throw new Error('Password verification failed');
  const noMatch = await bcrypt.compare('wrong-password', hash);
  if (noMatch) throw new Error('Wrong password should not match');
});

// Test 2: sharp (N-API image processing with libvips)
test('sharp (image processing)', async () => {
  const sharp = require('sharp');

  // Create a simple test image
  const { data, info } = await sharp({
    create: {
      width: 100,
      height: 100,
      channels: 3,
      background: { r: 255, g: 0, b: 0 }
    }
  })
    .png()
    .toBuffer({ resolveWithObject: true });

  if (info.width !== 100 || info.height !== 100) {
    throw new Error(`Unexpected dimensions: ${info.width}x${info.height}`);
  }

  // Resize the image
  const resized = await sharp(data).resize(50, 50).toBuffer();
  const resizedInfo = await sharp(resized).metadata();

  if (resizedInfo.width !== 50 || resizedInfo.height !== 50) {
    throw new Error(`Resize failed: ${resizedInfo.width}x${resizedInfo.height}`);
  }
});

// Test 3: @napi-rs/uuid (Rust-based N-API)
test('@napi-rs/uuid (Rust N-API)', async () => {
  const { v4: uuidv4 } = require('@napi-rs/uuid');

  const uuid1 = uuidv4();
  const uuid2 = uuidv4();

  // Basic UUID format validation
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  if (!uuidRegex.test(uuid1)) throw new Error('Invalid UUID format: ' + uuid1);
  if (uuid1 === uuid2) throw new Error('UUIDs should be unique');
});

// Test 4: @node-rs/argon2 (Rust-based N-API password hashing)
test('@node-rs/argon2 (Rust N-API)', async () => {
  const { hash, verify } = require('@node-rs/argon2');

  const password = 'my-secure-password';
  const hashed = await hash(password);

  if (!hashed.startsWith('$argon2')) {
    throw new Error('Invalid argon2 hash format');
  }

  const isValid = await verify(hashed, password);
  if (!isValid) throw new Error('Password verification failed');

  const isInvalid = await verify(hashed, 'wrong-password');
  if (isInvalid) throw new Error('Wrong password should not verify');
});

runTests();
