/**
 * Check if each worker thread has its own 4GB heap limit
 */

const { Worker, isMainThread, parentPort, workerData } = require('worker_threads');
const v8 = require('v8');

const NUM_WORKERS = 4;

if (isMainThread) {
  console.log('=== Worker Heap Limits Test ===\n');

  const mainStats = v8.getHeapStatistics();
  console.log('Main thread:');
  console.log(`  Heap size limit: ${(mainStats.heap_size_limit / 1024 / 1024 / 1024).toFixed(2)} GB`);
  console.log(`  Physical memory: ${(mainStats.total_physical_size / 1024 / 1024).toFixed(2)} MB\n`);

  const workers = [];
  const results = [];

  for (let i = 0; i < NUM_WORKERS; i++) {
    const worker = new Worker(__filename, {
      workerData: { workerId: i }
    });

    worker.on('message', (msg) => {
      results.push(msg);
    });

    workers.push(worker);
  }

  Promise.all(workers.map(w => new Promise(resolve => w.on('exit', resolve))))
    .then(() => {
      console.log('Worker heap limits:');
      results.sort((a, b) => a.workerId - b.workerId);
      results.forEach(r => {
        console.log(`  Worker ${r.workerId}: ${r.heapLimitGB.toFixed(2)} GB`);
      });

      const totalLimit = results.reduce((sum, r) => sum + r.heapLimitGB, 0) +
                        (mainStats.heap_size_limit / 1024 / 1024 / 1024);
      console.log(`\nTheoretical total heap available: ${totalLimit.toFixed(2)} GB`);
      console.log(`(Main + ${NUM_WORKERS} workers × 4GB each = ${(1 + NUM_WORKERS) * 4} GB max)`);

      if (results.every(r => r.heapLimitGB >= 3.9)) {
        console.log('\n✓ Each worker has its own ~4GB heap limit');
        console.log('  You CAN exceed 4GB total by using multiple workers/isolates');
      }
    });

} else {
  const { workerId } = workerData;
  const stats = v8.getHeapStatistics();

  parentPort.postMessage({
    workerId,
    heapLimitGB: stats.heap_size_limit / 1024 / 1024 / 1024
  });
}
