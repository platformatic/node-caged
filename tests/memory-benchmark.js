/**
 * Memory benchmark to observe pointer compression effects.
 *
 * Creates arrays of objects to measure memory usage patterns.
 * With pointer compression, object pointers use 32 bits instead of 64 bits,
 * resulting in lower memory usage for pointer-heavy data structures.
 */

const v8 = require('v8');

function formatBytes(bytes) {
  return (bytes / 1024 / 1024).toFixed(2) + ' MB';
}

function getMemoryUsage() {
  if (global.gc) {
    global.gc();
  }
  return v8.getHeapStatistics().used_heap_size;
}

function runBenchmark(name, createFn, count) {
  console.log(`\n--- ${name} ---`);

  const before = getMemoryUsage();
  const data = createFn(count);
  const after = getMemoryUsage();

  const used = after - before;
  const perItem = used / count;

  console.log(`  Items created: ${count.toLocaleString()}`);
  console.log(`  Memory before: ${formatBytes(before)}`);
  console.log(`  Memory after:  ${formatBytes(after)}`);
  console.log(`  Memory used:   ${formatBytes(used)}`);
  console.log(`  Bytes per item: ${perItem.toFixed(2)}`);

  return { data, used, perItem };
}

console.log('=== Memory Benchmark for Pointer Compression ===');
console.log(`Node.js ${process.version}`);
console.log(`V8 ${process.versions.v8}`);

const COUNT = 1_000_000;

// Benchmark 1: Array of simple objects (pointer-heavy)
runBenchmark('Array of Objects', (n) => {
  const arr = [];
  for (let i = 0; i < n; i++) {
    arr.push({ value: i });
  }
  return arr;
}, COUNT);

// Benchmark 2: Array of nested objects (more pointers)
runBenchmark('Nested Objects', (n) => {
  const arr = [];
  for (let i = 0; i < n; i++) {
    arr.push({
      data: { inner: { value: i } }
    });
  }
  return arr;
}, COUNT / 2);

// Benchmark 3: Linked list structure (maximum pointer overhead)
runBenchmark('Linked List', (n) => {
  let head = { value: 0, next: null };
  let current = head;
  for (let i = 1; i < n; i++) {
    current.next = { value: i, next: null };
    current = current.next;
  }
  return head;
}, COUNT / 2);

// Benchmark 4: Array of arrays (reference-heavy)
runBenchmark('Array of Arrays', (n) => {
  const arr = [];
  for (let i = 0; i < n; i++) {
    arr.push([i, i + 1, i + 2]);
  }
  return arr;
}, COUNT / 2);

console.log('\n=== Benchmark Complete ===');
console.log('\nNote: Run with --expose-gc flag for accurate measurements:');
console.log('  node --expose-gc memory-benchmark.js');
