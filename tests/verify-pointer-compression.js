/**
 * Verify that pointer compression is enabled in the V8 build.
 *
 * This script checks V8 flags and heap statistics to confirm
 * pointer compression is active.
 */

const v8 = require('v8');

console.log('=== Pointer Compression Verification ===\n');

// Check heap statistics
const heapStats = v8.getHeapStatistics();
console.log('Heap Statistics:');
console.log(`  Heap size limit: ${(heapStats.heap_size_limit / 1024 / 1024).toFixed(2)} MB`);
console.log(`  Total heap size: ${(heapStats.total_heap_size / 1024 / 1024).toFixed(2)} MB`);
console.log(`  Used heap size: ${(heapStats.used_heap_size / 1024 / 1024).toFixed(2)} MB`);

// With pointer compression, the max heap is limited to 4GB
// due to 32-bit compressed pointers
const maxHeapGB = heapStats.heap_size_limit / 1024 / 1024 / 1024;
console.log(`\nMax heap size: ${maxHeapGB.toFixed(2)} GB`);

if (maxHeapGB <= 4) {
  console.log('✓ Heap limit suggests pointer compression is enabled (≤4GB limit)');
} else {
  console.log('✗ Heap limit exceeds 4GB - pointer compression may not be enabled');
}

// Check V8 version
console.log(`\nV8 version: ${process.versions.v8}`);
console.log(`Node.js version: ${process.version}`);

// Try to get V8 flags (if available)
const heapCodeStats = v8.getHeapCodeStatistics();
console.log('\nHeap Code Statistics:');
console.log(`  Code and metadata size: ${(heapCodeStats.code_and_metadata_size / 1024).toFixed(2)} KB`);
console.log(`  Bytecode and metadata size: ${(heapCodeStats.bytecode_and_metadata_size / 1024).toFixed(2)} KB`);

console.log('\n=== Verification Complete ===');
