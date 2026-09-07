// Two files carry the whole client: keep them honest.
import { statSync } from "node:fs";
const gates = [["public/style.css", 12288], ["public/deck.js", 14336]];
let failed = false;
for (const [file, max] of gates) {
  const size = statSync(new URL(`../${file}`, import.meta.url)).size;
  const ok = size <= max;
  console.log(`${ok ? "ok " : "BIG"} ${file} ${size} / ${max} bytes`);
  if (!ok) failed = true;
}
process.exit(failed ? 1 : 0);
