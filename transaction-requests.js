/* Phase 1A: stable request identity for retry-safe writes.
   Persist only request ID and payload digest (never transaction amounts or notes). */
(function(root) {
  "use strict";
  const prefix="dhaftar-pending-v1:";
  function keyFor(userId,scope) {
    if (!userId || !/^[a-z-]+$/.test(scope)) throw new Error("Missing transaction identity.");
    return prefix+userId+":"+scope;
  }
  async function begin(userId,scope,payload) {
    const key=keyFor(userId,scope);
    const bytes=new TextEncoder().encode(JSON.stringify(payload));
    const digest=Array.from(new Uint8Array(await root.crypto.subtle.digest("SHA-256",bytes)),b=>b.toString(16).padStart(2,"0")).join("");
    const allocate=()=>{
      const raw=root.localStorage.getItem(key);
      if(raw) {
        const pending=JSON.parse(raw);
        if(!pending.id || !pending.digest) throw new Error("Pending request storage is invalid. Review your transaction history before clearing it.");
        if(pending.digest!==digest) throw new Error("An earlier submission is unresolved. Re-enter its original details and retry before starting another transaction.");
        return {key,id:pending.id};
      }
      const pending={id:root.crypto.randomUUID(),digest};
      root.localStorage.setItem(key,JSON.stringify(pending));
      return {key,id:pending.id};
    };
    return root.navigator?.locks?.request ? root.navigator.locks.request(key,allocate) : allocate();
  }
  function finish(request) {
    if (!request) return;
    const raw=root.localStorage.getItem(request.key);
    if(raw && JSON.parse(raw).id===request.id) root.localStorage.removeItem(request.key);
  }
  function definiteRejection(error) {
    // These server responses indicate that the transaction failed, not a lost response.
    return ["22023","22001","22003","23502","23503","23514","42501","P0001","PGRST202"].includes(String(error?.code||""));
  }
  root.DhaftarRequests=Object.freeze({begin,finish,definiteRejection});
})(globalThis);
