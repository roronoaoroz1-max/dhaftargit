import assert from "node:assert/strict";import vm from "node:vm";import {readFileSync} from "node:fs";
const read=p=>readFileSync(new URL("../"+p,import.meta.url),"utf8");
const source=read("dhaftar-sections.js");
for(const page of ["amanah.html","admin.html","stock.html","spending.html"]){
 const h=read(page);assert.ok(h.includes("DhaftarSections.init()"));for(const m of h.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi))if(m[1].trim())new vm.Script(m[1]);
 const map=new Map(),listeners={};const make=()=>({classes:new Set(),children:[],attributes:{},classList:{toggle(k,v){this.owner.classes[v?"add":"delete"](k)}},setAttribute(k,v){this.attributes[k]=v},append(n){this.children.push(n)},addEventListener(k,f){this[k]=f},contains(n){return this===n||this.children.includes(n)}});
 const ctx=vm.createContext({location:{pathname:"/"+page,hash:""},document:{getElementById:id=>id===config.root?host:map.get("#"+id),createElement:()=>make()},addEventListener:(k,f)=>listeners[k]=f});
 vm.runInContext(source,ctx);const config=ctx.DhaftarSections.configs[page];let bar;
 const host={querySelectorAll:s=>map.has(s)?[map.get(s)]:[]};
 for(const [, ,selectors] of config.tabs)for(const s of selectors){const n=make();n.classList.owner=n;n.parentNode={insertBefore:b=>bar=b};map.set(s,n);if(s.startsWith("#"))assert.ok(h.includes('id="'+s.slice(1)+'"'));else if(s.startsWith("."))assert.ok(h.includes(s.slice(1)));else assert.ok(h.includes(s.match(/="([^"]+)"/)[1]));}
 ctx.DhaftarSections.init();assert.equal(bar.children.length,config.tabs.length);
 const first=map.get(config.tabs[0][2][0]),last=map.get(config.tabs.at(-1)[2][0]);first.value="unfinished";assert.equal(first.classes.has("dx-section-hidden"),false);assert.equal(last.classes.has("dx-section-hidden"),true);
 assert.equal(ctx.DhaftarSections.reveal(last),true);assert.equal(last.classes.has("dx-section-hidden"),false);assert.equal(first.classes.has("dx-section-hidden"),true);
 assert.equal(ctx.DhaftarSections.select(config.tabs[0][0]),true);assert.equal(first.value,"unfinished");assert.equal(first.classes.has("dx-section-hidden"),false);
 assert.equal(ctx.DhaftarSections.select("invalid"),false);
}
assert.ok(read("dhaftar-ux.js").includes("DhaftarSections?.reveal(target)"));assert.ok(read("admin.html").includes("DhaftarSections?.reveal(target)"));assert.ok(read("amanah.html").includes('DhaftarSections?.reveal(repaymentElement("repaymentForm"))'));
console.log("PASS: four module section switches, deep-link integration, draft retention and syntax");
