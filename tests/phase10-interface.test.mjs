import assert from "node:assert/strict";
import vm from "node:vm";
import {readFileSync} from "node:fs";
const read=p=>readFileSync(new URL("../"+p,import.meta.url),"utf8");
const source=read("dhaftar-smart.js");
const elements=new Map(),all=[],listeners={},stored=new Map();let authCallback,uid="user-a",pending=false;
function make(tag){const n={tagName:tag.toUpperCase(),children:[],value:"",textContent:"",hidden:false,open:false,events:{},classList:{contains:()=>false},setAttribute(){},append(...x){this.children.push(...x)},prepend(x){this.children.unshift(x)},replaceChildren(){this.children=[]},addEventListener(k,f){this.events[k]=f},dispatchEvent(){},focus(){},click(){this.events.click?.()},showModal(){this.open=true},close(){this.open=false;this.events.close?.()},querySelector(s){if(s===".dx-draft-tools")return this.children.find(x=>x.className==="dx-draft-tools");if(s==="button")return this.children.find(x=>x.tagName==="BUTTON");if(s==="button:last-child")return this.children.filter(x=>x.tagName==="BUTTON").at(-1);return null;}};all.push(n);return n;}
const form=make("form");form.id="personalSavingsForm";elements.set(form.id,form);
for(const id of ["personalSavingsType","personalSavingsAmount","personalSavingsDate","personalSavingsNote"]){const n=make("input");n.form=form;elements.set(id,n);}
const ctx=vm.createContext({document:{body:make("body"),getElementById:id=>elements.get(id)||null,createElement:make,querySelector:()=>null},Event:class{},confirm:()=>true,addEventListener:(k,f)=>listeners[k]=f,sessionStorage:{get length(){return stored.size},key:i=>[...stored.keys()][i],getItem:k=>stored.get(k)||null,setItem:(k,v)=>stored.set(k,v),removeItem:k=>stored.delete(k)},DhaftarRequests:{hasPending:()=>pending},DhaftarNotifications:{hasAccess:()=>true}});
vm.runInContext(source,ctx);
assert.equal(ctx.DhaftarSmart.pattern("a%b_c"),"%a\\%b\\_c%");
assert.match(ctx.DhaftarSmart.today(),/^\d{4}-\d{2}-\d{2}$/);
ctx.DhaftarSmart.bind({auth:{getSession:async()=>({data:{session:{user:{id:uid}}}}),onAuthStateChange:f=>authCallback=f}});
await new Promise(r=>setImmediate(r));
assert.match(elements.get("personalSavingsDate").value,/^\d{4}-\d{2}-\d{2}$/);
const buttons=form.querySelector(".dx-draft-tools").children;
elements.get("personalSavingsAmount").value="100";
buttons[0].click();assert.equal(stored.size,1);
elements.get("personalSavingsAmount").value="200";
pending=true;buttons[1].click();assert.equal(elements.get("personalSavingsAmount").value,"200");
pending=false;buttons[1].click();assert.equal(elements.get("personalSavingsAmount").value,"100");
ctx.DhaftarSmart.saved(form.id,"user-b");assert.equal(stored.size,1);
ctx.DhaftarSmart.saved(form.id,"user-a");assert.equal(stored.size,0);
buttons[0].click();assert.equal(stored.size,1);
const toolbar=all.find(n=>n.className==="dx-smart-tools"),cover=all.find(n=>n.className==="dx-privacy-cover");
toolbar.children[2].click();assert.equal(cover.open,true);cover.querySelector("button").click();assert.equal(cover.open,false);
authCallback("SIGNED_OUT",null);assert.equal(stored.size,0);assert.equal(toolbar.hidden,true);
for(const page of ["index.html","admin.html","amanah.html","stock.html","spending.html","today.html","statements.html"]){const h=read(page);assert.ok(h.includes("DhaftarSmart.bind(supabaseClient)"));for(const m of h.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi))if(m[1].trim())new vm.Script(m[1]);}
console.log("PASS: smart forms, pending request guard, owner scoped draft cleanup, privacy and integration");
