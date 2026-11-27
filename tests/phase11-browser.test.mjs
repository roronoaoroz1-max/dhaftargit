import {chromium,webkit} from "playwright";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {createServer} from "node:http";
import {resolve,extname} from "node:path";
const dir=process.cwd(),pages=["index.html","admin.html","amanah.html","stock.html","spending.html","today.html","statements.html"];
const server=createServer(async(req,res)=>{try{const p=resolve(dir,"."+new URL(req.url,"http://localhost").pathname);if(!p.startsWith(dir+"/"))throw Error("path");const data=await readFile(p);res.setHeader("Content-Type",({".html":"text/html",".js":"text/javascript",".css":"text/css",".png":"image/png",".svg":"image/svg+xml",".webmanifest":"application/manifest+json"})[extname(p)]||"application/octet-stream");res.end(data);}catch{res.statusCode=404;res.end();}});
await new Promise(r=>server.listen(0,"127.0.0.1",r));
const base="http://127.0.0.1:"+server.address().port;
const stub=String.raw`
window.supabase={createClient(){const u={id:"10000000-0000-4000-8000-000000000001",email:"fixture@example.invalid"};let session={user:u};const callbacks=[];
const profile={id:u.id,role:"admin",email:u.email,full_name:"Fixture administrator"};
function query(table){let single=false;const q={};for(const k of ["select","eq","neq","is","in","gte","gt","lte","lt","order","limit","range","ilike","match","or","filter"])q[k]=()=>q;q.single=q.maybeSingle=()=>{single=true;return q};q.then=(ok,bad)=>Promise.resolve({data:table==="profiles"?profile:single?null:[],error:null,count:0}).then(ok,bad);return q;}
const totals=[{currency:"MVR",net_worth:100,savings:40,total_liabilities:20,total_assets:120},{currency:"USD",net_worth:5,savings:0,total_liabilities:0,total_assets:5}];
return {auth:{getSession:async()=>({data:{session},error:null}),getUser:async()=>({data:{user:session?.user},error:null}),onAuthStateChange:f=>{callbacks.push(f);return {data:{subscription:{unsubscribe(){}}}}},signOut:async()=>{session=null;callbacks.forEach(f=>f("SIGNED_OUT",null));return {error:null}}},from:query,rpc:async(name,args)=>{let data=[];if(name==="dhaftar_notifications_v6")data={today:"2026-11-27",notifications:[],unread:0,attention:0};else if(name==="dhaftar_net_worth_v5")data=totals;else if(name==="dhaftar_savings_balance_v1")data=40;else if(name==="get_dhaftar_summary")data={success:true,through:{month:"November",year:2026},unpaidMonths:0,billBreakdown:[],totalAmountDue:0,totalPaid:0,remainingBalance:0};else if(name==="dhaftar_payment_history_v1")data={rows:[],page:1,page_count:1,payers:[],total_count:0,total_amount:0};else if(/medication/.test(name))data=null;return {data,error:null};}};
}};
`;
try{
for(const [engine,type] of [["chromium",chromium],["webkit",webkit]]){
 const browser=await type.launch({headless:true});
 try{const context=await browser.newContext({viewport:{width:390,height:844},deviceScaleFactor:2,isMobile:true,hasTouch:true});
 await context.route("**/*",async route=>{const url=route.request().url();if(url.startsWith(base+"/"))return route.continue();if(url.includes("@supabase/supabase-js"))return route.fulfill({contentType:"text/javascript",body:stub});return route.abort();});
 const p=await context.newPage(),errors=[];p.on("pageerror",e=>errors.push(e.message));
 for(const file of pages){errors.length=0;const start=Date.now();await p.goto(base+"/"+file,{waitUntil:"load"});await p.locator(".dx-nav").waitFor({state:"visible",timeout:12000});await p.locator(".dx-smart-tools").waitFor({state:"visible",timeout:12000});const ms=Date.now()-start;assert.ok(ms<15000,file+" shell load timeout");assert.equal(await p.locator(".dx-nav button").count(),2);assert.ok(await p.locator(".dx-nav").getAttribute("aria-label"));assert.ok(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+2),file+" horizontal overflow");assert.deepEqual(errors,[],file+" uncaught errors");console.log(engine,file,"mobile shell ready",ms+"ms");}
 await p.goto(base+"/spending.html");await p.locator(".dx-section-nav").waitFor({state:"visible"});await p.locator("#amount").fill("123.45");await p.getByRole("button",{name:"Insights",exact:true}).click();await p.getByRole("button",{name:"Add spending",exact:true}).click();assert.equal(await p.locator("#amount").inputValue(),"123.45");
 await p.getByRole("button",{name:"Privacy",exact:true}).click();await p.locator(".dx-privacy-cover[open]").waitFor();await p.getByRole("button",{name:"Show Dhaftar",exact:true}).click();assert.equal(await p.locator(".dx-privacy-cover[open]").count(),0);
 await p.locator(".dx-nav").getByRole("button",{name:"Add",exact:true}).click();await p.getByRole("link",{name:"Household payment",exact:true}).click();await p.locator("#paymentCard").waitFor({state:"visible"});assert.equal(await p.locator(".dx-section-nav button[aria-pressed=true]").textContent(),"Payment");
 await context.close();}finally{await browser.close();}
}
}finally{server.close();}
