/// <reference path="../worker-configuration.d.ts" />

export type Bindings = {
  CATALOG: D1Database;
  NOTES: D1Database;
  ASSETS: Fetcher;
  RP_NAME: string;
  ADMIN_HANDLES: string;
  SEARCH_MODE?: string;
  RP_ID_OVERRIDE?: string;
  /** The Services ID the website uses for Sign in with Apple (Apple developer portal). */
  APPLE_WEB_CLIENT_ID?: string;
  /** The app's bundle id — the audience of tokens the iPhone sends. */
  APPLE_APP_BUNDLE_ID?: string;
};

/** The signed-in head, resolved once per request from the session cookie. */
export interface Head {
  id: string;
  handle: string;
  role: string;
  shareSpins: boolean;
  firstShow: string | null;
  notesSeenThrough: number;
  isAdmin: boolean;
}

export type Vars = { head: Head | null };
export type App = { Bindings: Bindings; Variables: Vars };
