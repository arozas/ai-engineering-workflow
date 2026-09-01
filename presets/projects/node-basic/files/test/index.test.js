import assert from "node:assert/strict";
import test from "node:test";

import { greet } from "../src/index.js";

test("greets a valid name", () => {
  assert.equal(greet("Alejandro"), "Hello, Alejandro!");
});

test("rejects an empty name", () => {
  assert.throws(() => greet("  "), TypeError);
});
