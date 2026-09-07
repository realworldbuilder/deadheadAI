/// <reference types="@cloudflare/vitest-pool-workers/types" />
declare namespace Cloudflare {
  interface Env {
    TEST_MIGRATIONS: import("@cloudflare/vitest-pool-workers").D1Migration[];
  }
}
declare module "*.sql?raw" {
  const text: string;
  export default text;
}
