import assert from "node:assert/strict";
import {webcrypto} from "node:crypto";
import {readFileSync} from "node:fs";
import vm from "node:vm";
const source=readFileSync(new URL("../transaction-requests.js",import.meta.url),"utf8");
const data=new Map();
const storage={getItem:k=>data.get(k)??null,setItem:(k,v)=>data.set(k,v),removeItem:k=>data.delete(k)};
const load=()=>{const ctx=vm.createContext({crypto:webcrypto,TextEncoder,localStorage:storage});vm.runInContext(source,ctx);return ctx.DhaftarRequests;};
let api=load();
const first=await api.begin("test-user","stock-purchase",["item",2,100]);
assert.equal(api.hasPending("test-user","stock-purchase"),true);
api=load();
assert.equal((await api.begin("test-user","stock-purchase",["item",2,100])).id,first.id);
await assert.rejects(api.begin("test-user","stock-purchase",["item",3,100]),/unresolved/);
const other=await api.begin("other-user","stock-purchase",["item",2,100]);
assert.notEqual(other.id,first.id);
const savings=await api.begin("test-user","personal-savings",["deposit",100]);
assert.notEqual(savings.id,first.id);
api.finish(first);
assert.equal(api.hasPending("test-user","stock-purchase"),false);
const newRequest=await api.begin("test-user","stock-purchase",["item",2,100]);
assert.notEqual(newRequest.id,first.id);
api.finish(first);
assert.equal(api.hasPending("test-user","stock-purchase"),true);
assert.equal(api.definiteRejection({code:"23514"}),true);
assert.equal(api.definiteRejection(new Error("Network error")),false);
for(const path of ["stock.html","amanah.html","admin.html","spending.html"]){
 const html=readFileSync(new URL("../"+path,import.meta.url),"utf8");
 for(const match of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)){
   if(!/\bsrc\s*=/.test(match[1])&&!/type\s*=\s*["'](?:module|application\/json)/i.test(match[1]))new vm.Script(match[2],{filename:path});
 }
}
console.log("PASS: persistent request identity, scope separation, mismatched payload, clearing, rejection classification and four page syntax checks");
