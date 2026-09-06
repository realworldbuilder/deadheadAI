/** The tape deck's markup. Hidden until deck.js has something cued. */
import type { FC } from "hono/jsx";

export const Deck: FC = () => (
  <aside class="deck" id="deck" aria-label="Tape deck" hidden>
    <div class="deck-in">
      <div class="deck-ctl" role="group" aria-label="Transport">
        <button type="button" data-deck="prev" aria-label="Previous tune">⏮</button>
        <button type="button" data-deck="back" aria-label="Back 15 seconds">◀15</button>
        <button type="button" class="deck-play" data-deck="toggle" aria-label="Play">▶</button>
        <button type="button" data-deck="fwd" aria-label="Ahead 15 seconds">15▶</button>
        <button type="button" data-deck="next" aria-label="Next tune">⏭</button>
      </div>
      <div class="deck-now" aria-live="polite">
        <a class="deck-title" data-deck="link" href="/">Nothing cued</a>
        <span class="deck-sub" data-deck="sub"></span>
      </div>
      <div class="deck-time">
        <span data-deck="pos">0:00</span> / <span data-deck="dur">--:--</span>
      </div>
      <div class="deck-seek">
        <label class="vh" for="deck-seek">Position</label>
        <input id="deck-seek" type="range" min="0" max="1000" value="0" data-deck="seek" />
      </div>
      <div class="deck-more">
        <label class="vh" for="deck-sleep">Sleep timer</label>
        <select id="deck-sleep" data-deck="sleep">
          <option value="0">Sleep: off</option>
          <option value="15">15 min</option>
          <option value="30">30 min</option>
          <option value="45">45 min</option>
          <option value="60">60 min</option>
          <option value="end">End of this tune</option>
        </select>
        <button type="button" data-deck="eject" aria-label="Eject the tape">Eject</button>
      </div>
      <p class="deck-msg" data-deck="msg" role="status"></p>
    </div>
  </aside>
);
