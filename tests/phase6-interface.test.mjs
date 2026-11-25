import assert from "node:assert/strict";import vm from "node:vm";import {readFileSync} from "node:fs";
const read=p=>readFileSync(new URL("../"+p,import.meta.url),"utf8");const ctx=vm.createContext({});vm.runInContext(read("notifications.js"),ctx);
const rows=[{category:"stock",urgency:"today",snoozed:false,read_at:null},{category:"household",urgency:"upcoming",snoozed:false,read_at:"date"},{category:"medication",urgency:"overdue",snoozed:true,read_at:null}];
assert.equal(ctx.DhaftarNotifications.visible(rows,"active","all").length,2);assert.equal(ctx.DhaftarNotifications.visible(rows,"unread","all").length,1);assert.equal(ctx.DhaftarNotifications.visible(rows,"snoozed","all").length,1);assert.equal(ctx.DhaftarNotifications.visible(rows,"today","all").length,1);
for(const file of ["today.html","index.html","admin.html","stock.html","spending.html","amanah.html","statements.html"]){const h=read(file);assert.ok(h.includes('src="notifications.js"'),file);assert.ok(h.includes("DhaftarNotifications.bind("),file);for(const m of h.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi))if(m[1].trim())new vm.Script(m[1]);}
console.log("PASS: notification filters, syntax and page integration");
