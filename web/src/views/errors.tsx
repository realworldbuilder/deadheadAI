import type { FC } from "hono/jsx";
import type { CatalogShow } from "../catalog/queries";
import { prettyDate } from "../fmt";
import { ShowRows } from "./parts";

export const NotFound: FC = () => (
  <>
    <p class="meta">404</p>
    <h1>Nothing here.</h1>
    <p>No show, no note, no head at that address. Try <a href="/search">Search</a> or <a href="/years">the years</a>.</p>
  </>
);

export const NoShowThatNight: FC<{ date: string; nearest: CatalogShow[] }> = ({ date, nearest }) => (
  <>
    <h1>The Dead didn't play {prettyDate(date)}.</h1>
    {nearest.length ? <><p>Nearest nights:</p><ShowRows shows={nearest} /></> : null}
  </>
);

export const Forbidden: FC<{ what?: string }> = ({ what }) => (
  <>
    <h1>{what ?? "That page isn't yours."}</h1>
    <p>Sign in as the head it belongs to, or head <a href="/">back to the front</a>.</p>
  </>
);

export const Broke: FC = () => (
  <>
    <h1>Bummer.</h1>
    <p>Something broke on our end, not yours. Try again in a minute.</p>
  </>
);
