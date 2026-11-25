import assert from "node:assert/strict";import vm from "node:vm";import {readFileSync} from "node:fs";
const read=p=>readFileSync(new URL("../"+p,import.meta.url),"utf8");
const admin=read("admin.html"),index=read("index.html"),source=read("recurring-payments.js");
new vm.Script(source);const ids=new Set([...admin.matchAll(/\bid="([^"]+)"/g)].map(m=>m[1]));
for(const m of source.matchAll(/\bel\("([^"]+)"\)/g))assert.ok(ids.has(m[1]),"Missing ID "+m[1]);
for(const html of [admin,index])for(const m of html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi))if(m[1].trim())new vm.Script(m[1]);
assert.ok(admin.includes('src="recurring-payments.js"'));assert.ok(admin.includes('RecurringPayments.bind('));assert.ok(admin.includes('dhaftar_setup_month_v3'));assert.ok(index.includes('dhaftar_medication_renew_v3'));
console.log("PASS: Phase 3 scripts, element IDs and integration");
