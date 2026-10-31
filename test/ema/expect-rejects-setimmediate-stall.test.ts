import { afterAll, expect, test } from "bun:test";
import { createServer } from "node:net";

// Anything that keeps the event loop active. Without one, the nested loop
// never blocks in the poll and nothing stalls. In real programs this is a pg /
// ioredis / keep-alive HTTP socket.
const server = createServer().listen(0);
afterAll(() => server.close());

// One hop = a promise resolved from inside a setImmediate callback (this is
// what JSZip's internal streams do between chunks).
const hop = () => new Promise<void>(resolve => setImmediate(resolve));

async function work(hops: number, gaps: number[]) {
  for (let i = 0; i < hops; i++) {
    const t = performance.now();
    await hop();
    gaps.push(performance.now() - t);
  }
  (globalThis as any).settledAt = performance.now();
  throw new Error("done");
}

const report = (name: string, gaps: number[], afterSettle: number) => {
  const worst = Math.max(...gaps);
  console.log(
    `[${Bun.version}+${Bun.revision.slice(0, 9)}] ${name}: slowest hop ${worst.toFixed(0)}ms, ` +
      `settle->expect returns ${afterSettle.toFixed(0)}ms`,
  );
  return Math.max(worst, afterSettle);
};

// expect() called directly from the test body.
test("A: promise settled by an immediate's checkpoint is noticed promptly", async () => {
  for (let round = 0; round < 5; round++) {
    const gaps: number[] = [];
    await expect(work(3, gaps)).rejects.toThrow("done");
    const worst = report(`A round ${round}`, gaps, performance.now() - (globalThis as any).settledAt);
    expect(worst).toBeLessThan(100);
  }
});

// expect() called after an `await`, like any test that awaited I/O first.
test("B: microtasks queued by an immediate inside a nested wait are drained promptly", async () => {
  await Bun.sleep(1);
  for (let round = 0; round < 5; round++) {
    const gaps: number[] = [];
    await expect(work(3, gaps)).rejects.toThrow("done");
    const worst = report(`B round ${round}`, gaps, performance.now() - (globalThis as any).settledAt);
    expect(worst).toBeLessThan(100);
  }
});
