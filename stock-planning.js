/* Phase 4 stock planning. Forecasts are estimates, never measured inventory. */
(function(root){
 "use strict";
 const el=id=>document.getElementById(id);
 const node=(tag,text,cls)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=String(text);if(cls)n.className=cls;return n;};
 let cfg=null,target=null,saving=false,preferenceSaving=false;
 function forecast(item,a,horizon){
  const due=item.manualLow||a.statusKey==="buy-now"?0:a.daysLeft;
  if(due===null||!Number.isFinite(due)||due>horizon)return null;
  const qty=a.latest?.qty>0?a.latest.qty:null;
  const cost=qty!==null&&a.avgUnitPrice!==null&&Number.isFinite(a.avgUnitPrice)?Math.round(qty*a.avgUnitPrice):null;
  return {item,a,due,qty,cost};
 }
 function render(){
  if(!cfg)return;
  el("openBulkPurchase").disabled=!cfg.ready()||saving;
  const horizon=Number(el("forecastHorizon").value);
  const all=cfg.items().map(item=>({item,a:cfg.analytics(item)}));
  const rows=all.map(x=>forecast(x.item,x.a,horizon)).filter(Boolean).sort((a,b)=>a.due-b.due||a.item.name.localeCompare(b.item.name));
  const total=rows.reduce((s,r)=>s+(r.cost??0),0),unknown=rows.filter(r=>r.cost===null).length,learning=all.filter(x=>x.a.daysLeft===null&&!x.item.manualLow&&x.a.statusKey!=="buy-now").length;
  el("forecastTotal").textContent=cfg.money(total)+" estimated · "+rows.length+" item(s)"+(unknown?" · "+unknown+" without price estimate":"")+(learning?" · "+learning+" not yet predictable":"")+(cfg.ready()?"":" · Planning settings unavailable");
  const list=el("forecastRows");list.replaceChildren();
  for(const r of rows){
   const line=node("div",undefined,"shopping-row"),text=node("div");
   text.append(node("strong",r.item.name),node("span",(r.due<=0?"Buy now":"In "+r.due+" days")+" · "+(r.qty===null?"Quantity unknown":r.qty+" "+r.item.unit)+" · "+r.a.confidence+" confidence"+(r.item.preferredShop?" · "+r.item.preferredShop:"")));
   line.append(text,node("strong",r.cost===null?"Unknown":cfg.money(r.cost)));list.append(line);
  }
  if(!rows.length)list.append(node("p","No predicted next purchases in this period."));
  const history=el("stockVoidHistory");history.replaceChildren();
  const voids=cfg.allPurchases().filter(p=>p.voided_at).sort((a,b)=>String(b.voided_at).localeCompare(String(a.voided_at)));
  for(const p of voids)history.append(node("p",(cfg.names().get(p.stock_item_id)||"Archived item")+" · "+cfg.displayDate(p.purchased_on)+" · Quantity "+p.quantity+" · "+cfg.money(Math.round(Number(p.amount)*100))+" · Voided "+String(p.voided_at).slice(0,10)+" · "+(p.void_reason||"No reason recorded")));
  if(!voids.length)history.append(node("p","No voided purchases."));
 }
 function openPreferences(item){
  if(!cfg.ready()||preferenceSaving)return;
  target=item.id;el("stockPreferencesName").textContent=item.name;el("preferredShop").value=item.preferredShop||"";el("restockReminder").value=item.reminderDays??5;el("manualLow").checked=!!item.manualLow;el("preferencesStatus").textContent="";el("stockPreferencesDialog").showModal();
 }
 async function savePreferences(e){
  e.preventDefault();if(preferenceSaving||!cfg.ready()||!cfg.user())return;
  const days=Number(el("restockReminder").value);if(!Number.isInteger(days)||days<0||days>30){el("preferencesStatus").textContent="Enter 0–30 reminder days.";return;}
  preferenceSaving=true;const b=e.currentTarget.querySelector('button[type="submit"]');b.disabled=true;
  try{const r=await cfg.client.rpc("dhaftar_save_stock_preferences_v4",{p_item:target,p_shop:el("preferredShop").value.trim()||null,p_days:days,p_low:el("manualLow").checked});if(r.error)throw r.error;el("stockPreferencesDialog").close();await cfg.refresh();cfg.message("Stock preferences saved.");}
  catch(err){el("preferencesStatus").textContent=err.message||"Unable to save preferences.";}
  finally{preferenceSaving=false;b.disabled=false;}
 }
 function updateTotal(){
  let cents=0;for(const row of el("bulkLines").children){const v=row.querySelector('[data-field="amount"]').value;if(v!==""&&Number.isFinite(Number(v)))cents+=Math.round(Number(v)*100);}
  el("bulkTotal").textContent="Total: "+cfg.money(cents);
 }
 function addLine(){
  if(saving||el("bulkLines").children.length>=50)return;
  const row=node("div",undefined,"form-grid");row.style.margin="12px 0";
  const select=node("select");select.required=true;select.dataset.field="item";select.setAttribute("aria-label","Stock item");
  const blank=node("option","Choose item");blank.value="";select.append(blank);
  for(const item of cfg.items()){const o=node("option",item.name+" · "+item.unit);o.value=item.id;select.append(o);}
  const input=(type,field,placeholder,step,min)=>{const n=node("input");n.type=type;n.dataset.field=field;n.placeholder=placeholder;n.setAttribute("aria-label",placeholder);if(step)n.step=step;if(min!==undefined)n.min=min;return n;};
  const qty=input("number","quantity","Quantity","0.001","0.001"),amount=input("number","amount","Amount (MVR)","0.01","0"),note=input("text","note","Note (optional)");qty.required=amount.required=true;note.maxLength=120;
  const remove=node("button","Remove","button");remove.type="button";remove.addEventListener("click",()=>{if(!saving){row.remove();updateTotal();}});
  select.addEventListener("change",()=>{const item=cfg.items().find(x=>x.id===select.value);if(item&&!qty.value)qty.value=cfg.analytics(item).latest?.qty||"";});
  amount.addEventListener("input",updateTotal);row.append(select,qty,amount,note,remove);el("bulkLines").append(row);
 }
 function openBulk(){
  if(!cfg.ready()||saving)return;
  if(!el("bulkLines").children.length){el("bulkDate").value=cfg.today();addLine();}
  el("bulkDate").max=cfg.today();updateTotal();el("stockBulkDialog").showModal();
 }
 function validDecimal(raw,places,positive){
  const s=String(raw).trim();if(!new RegExp("^\\d+(?:\\.\\d{1,"+places+"})?$").test(s))return null;
  const n=Number(s),scaled=Math.round(n*10**places);
  return Number.isSafeInteger(scaled)&&scaled<1e14&&(positive?scaled>0:scaled>=0)?n:null;
 }
 async function recordBulk(e){
  e.preventDefault();if(saving||cfg.purchaseBusy()||!cfg.ready()||!cfg.user())return;
  const date=el("bulkDate").value,shop=el("bulkShop").value.trim()||null,lines=[];
  for(const row of el("bulkLines").children){
   const read=k=>row.querySelector('[data-field="'+k+'"]').value;
   const item=read("item"),qty=validDecimal(read("quantity"),3,true),amount=validDecimal(read("amount"),2,false);
   if(!item||qty===null||amount===null){el("bulkStatus").textContent="Check each item, quantity and amount.";return;}
   lines.push({item_id:item,quantity:qty,amount,note:read("note").trim()||null});
  }
  if(!date||date>cfg.today()||!lines.length||new Set(lines.map(x=>x.item_id)).size!==lines.length){el("bulkStatus").textContent="Use a valid date and one line per distinct item.";return;}
  lines.sort((a,b)=>a.item_id.localeCompare(b.item_id));const payload={p_date:date,p_shop:shop,p_lines:lines};
  saving=true;const b=e.currentTarget.querySelector('button[type="submit"]');b.disabled=true;let request=null,prior=true,saved=false;
  try{
   prior=root.DhaftarRequests.hasPending(cfg.user(),"stock-batch");
   request=await root.DhaftarRequests.begin(cfg.user(),"stock-batch",payload);
   const r=await cfg.client.rpc("dhaftar_record_stock_batch_v4",{p_id:request.id,...payload});if(r.error)throw r.error;
   saved=true;el("stockBulkDialog").close();el("bulkLines").replaceChildren();el("bulkShop").value="";el("bulkStatus").textContent="";
   root.DhaftarRequests.finish(request);await cfg.refresh();cfg.message("All "+lines.length+" purchases recorded.");
  }catch(err){
   if(!saved&&request&&!prior&&root.DhaftarRequests.definiteRejection(err)){try{root.DhaftarRequests.finish(request);}catch(_){}}
   el("bulkStatus").textContent=(err.message||"Unable to confirm batch.")+" Retry with the same details if uncertain.";
   if(saved)cfg.message("Batch saved; refresh Stock before another entry.",true);
  }finally{saving=false;b.disabled=false;render();}
 }
 function bind(options){
  cfg=options;el("forecastHorizon").addEventListener("change",render);el("openBulkPurchase").addEventListener("click",openBulk);el("addBulkLine").addEventListener("click",addLine);el("stockBulkForm").addEventListener("submit",recordBulk);el("stockPreferencesForm").addEventListener("submit",savePreferences);
 }
 root.StockPlanning=Object.freeze({bind,render,openPreferences,busy:()=>saving,forecast,validDecimal});
})(globalThis);
