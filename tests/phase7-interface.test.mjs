import assert from "node:assert/strict";import vm from "node:vm";import {readFileSync} from "node:fs";
const read=p=>readFileSync(new URL("../"+p,import.meta.url),"utf8");
const ctx=vm.createContext({});vm.runInContext(read("dhaftar-ux.js"),ctx);
assert.equal(ctx.DhaftarUX.current("admin.html#billStatusSection","admin.html"),true);
assert.equal(ctx.DhaftarUX.current("stock.html","index.html"),false);
const pages=["index.html","admin.html","amanah.html","stock.html","spending.html","statements.html","today.html"];
for(const page of pages){const h=read(page);assert.ok(h.includes('src="dhaftar-ux.js"'),page);assert.ok(h.includes('href="dhaftar-ux.css"'),page);assert.ok(h.includes("DhaftarUX.init()"),page);for(const m of h.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi))if(m[1].trim())new vm.Script(m[1]);}
for(const m of read("dhaftar-ux.js").matchAll(/\["([a-z]+\.html)#([A-Za-z][A-Za-z0-9_-]*)","[^"]+"\]/g))assert.ok(new RegExp('id\\s*=\\s*["\\x27]'+m[2]+'["\\x27]').test(read(m[1])),m[1]+" missing "+m[2]);
assert.ok(read("notifications.js").includes("hasAccess:()=>!!feed"));
console.log("PASS: navigation routes, integration, source anchors and syntax");