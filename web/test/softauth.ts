/**
 * A software authenticator for the tests: a P-256 key per credential,
 * attestation 'none', enough CBOR to build the attestation object. Drives
 * the real create/get ceremonies end to end.
 */
import { base64url, fromBase64url } from "../src/db/ids.ts";

const te = new TextEncoder();

function cbor(value: unknown): Uint8Array {
  const out: number[] = [];
  const head = (major: number, n: number) => {
    if (n < 24) out.push((major << 5) | n);
    else if (n < 256) out.push((major << 5) | 24, n);
    else if (n < 65536) out.push((major << 5) | 25, n >> 8, n & 255);
    else out.push((major << 5) | 26, (n >>> 24) & 255, (n >>> 16) & 255, (n >>> 8) & 255, n & 255);
  };
  const enc = (v: unknown) => {
    if (typeof v === "number") { if (v >= 0) head(0, v); else head(1, -1 - v); }
    else if (typeof v === "string") { const b = te.encode(v); head(3, b.length); out.push(...b); }
    else if (v instanceof Uint8Array) { head(2, v.length); out.push(...v); }
    else if (v instanceof Map) { head(5, v.size); for (const [k, x] of v) { enc(k); enc(x); } }
    else if (v && typeof v === "object") { const keys = Object.keys(v); head(5, keys.length); for (const k of keys) { enc(k); enc((v as Record<string, unknown>)[k]); } }
    else throw new Error("cbor: unsupported " + typeof v);
  };
  enc(value);
  return new Uint8Array(out);
}

function concat(...parts: Uint8Array[]): Uint8Array<ArrayBuffer> {
  const n = parts.reduce((s, p) => s + p.length, 0);
  const out = new Uint8Array(n);
  let o = 0;
  for (const p of parts) { out.set(p, o); o += p.length; }
  return out;
}

async function sha256(data: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", data));
}

function derSig(raw: Uint8Array): Uint8Array {
  const int = (b: Uint8Array) => {
    let i = 0;
    while (i < b.length - 1 && b[i] === 0) i++;
    let v = b.slice(i) as Uint8Array<ArrayBuffer>;
    if (v[0]! & 0x80) v = concat(new Uint8Array([0]), v);
    return concat(new Uint8Array([0x02, v.length]), v);
  };
  const r = int(raw.slice(0, 32)), s = int(raw.slice(32));
  return concat(new Uint8Array([0x30, r.length + s.length]), r, s);
}

export interface SoftCredential { id: string; keys: CryptoKeyPair; counter: number; rpId: string }

export class SoftAuthenticator {
  creds = new Map<string, SoftCredential>();

  async create(options: { rp: { id?: string }; challenge: string; user: { id: string } }, origin: string) {
    const rpId = options.rp.id ?? new URL(origin).hostname;
    const keys = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
    const idBytes = crypto.getRandomValues(new Uint8Array(16));
    const id = base64url(idBytes);
    this.creds.set(id, { id, keys, counter: 0, rpId });
    const raw = new Uint8Array((await crypto.subtle.exportKey("raw", keys.publicKey)) as ArrayBuffer);
    const cose = cbor(new Map<number, unknown>([[1, 2], [3, -7], [-1, 1], [-2, raw.slice(1, 33)], [-3, raw.slice(33, 65)]]));
    const authData = concat(await sha256(te.encode(rpId)), new Uint8Array([0x45]), new Uint8Array([0, 0, 0, 0]),
      new Uint8Array(16), new Uint8Array([idBytes.length >> 8, idBytes.length & 255]), idBytes, cose);
    const attestationObject = cbor({ fmt: "none", attStmt: {}, authData });
    const clientData = te.encode(JSON.stringify({ type: "webauthn.create", challenge: options.challenge, origin, crossOrigin: false }));
    return {
      id, rawId: id, type: "public-key", authenticatorAttachment: "platform", clientExtensionResults: {},
      response: { clientDataJSON: base64url(clientData), attestationObject: base64url(attestationObject), transports: ["internal"] },
    };
  }

  async get(options: { rpId?: string; challenge: string; allowCredentials?: { id: string }[] }, origin: string, credentialId?: string) {
    const id = credentialId ?? options.allowCredentials?.[0]?.id ?? [...this.creds.keys()][0]!;
    const cred = this.creds.get(id);
    if (!cred) throw new Error("no such credential");
    cred.counter += 1;
    const rpId = options.rpId ?? cred.rpId;
    const authData = concat(await sha256(te.encode(rpId)), new Uint8Array([0x05]),
      new Uint8Array([(cred.counter >>> 24) & 255, (cred.counter >>> 16) & 255, (cred.counter >>> 8) & 255, cred.counter & 255]));
    const clientData = te.encode(JSON.stringify({ type: "webauthn.get", challenge: options.challenge, origin, crossOrigin: false }));
    const toSign = concat(authData, await sha256(clientData));
    const raw = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, cred.keys.privateKey, toSign));
    return {
      id, rawId: id, type: "public-key", authenticatorAttachment: "platform", clientExtensionResults: {},
      response: { clientDataJSON: base64url(clientData), authenticatorData: base64url(authData), signature: base64url(derSig(raw)), userHandle: null },
    };
  }
}

export { fromBase64url };
