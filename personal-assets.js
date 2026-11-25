/* Phase 5 personal assets: owner-only, manual values, no cash ledger writes. */
(function(root){
"use strict";
const el=id=>document.getElementById(id);
const node=(tag,t,cls)=>{const n=document.createElement(tag);if(t!==undefined)n.textContent=String(t);if(cls)n.className=cls;return n;};
const labels={physical:"Physical asset",investment:"Investment",external_cash:"Other cash",external_liability:"External liability"};
let cfg=null,assets=[],totals=[],events=[],snapshots=[],selected=null,epoch=0,ready=false,busy=false;
function today(){const p=new Intl.DateTimeFormat("en-CA",{timeZone:"Indian/Maldives",year:"numeric",month:"2-digit",day:"2-digit"}).formatToParts(new Date());return ["year","month","day"].map(k=>p.find(x=>x.type===k).value).join("-");}
function amount(raw){const s=String(raw).trim();if(!/^\d+(?:\.\d{1,2})?$/.test(s))return null;const n=Math.round(Number(s)*100);return Number.isSafeInteger(n)&&n>=0&&n<1e14?n/100:null;}
function status(id,t,error=false){el(id).textContent=t;el(id).className=error?"goal-error":"goal-status";}
function clear(){++epoch;ready=false;assets=[];totals=[];events=[];snapshots=[];selected=null;el("assetContent").hidden=true;el("assetEventForm").hidden=true;for(const id of ["assetCards","netWorthTotals","assetHistory","netSnapshotHistory"])el(id).replaceChildren();status("assetStatus","Sign in to view personal assets.");}
function tile(title,value,detail){const n=node("div",undefined,"goal-tile");n.append(node("small",title),node("strong",value));if(detail)n.append(node("small",detail));return n;}
function money(v,c){return cfg.money(v,c);}
function renderCards(){
 const filter=el("assetFilter").value,box=el("assetCards");box.replaceChildren();
 for(const a of assets.filter(a=>filter==="retired"?a.retired:!a.retired&&(filter==="all"||a.kind===filter))){
 const n=tile(a.name,money(a.current_value,a.currency),labels[a.kind]+" · Valued "+a.valuation_date);
 n.append(node("small","Original cost / principal: "+money(a.acquisition_cost,a.currency)));
 if(a.note)n.append(node("p",a.note));
 if(a.kind==="physical"){n.append(node("small","Maintenance total: "+money(a.maintenance_total,a.currency)));if(a.next_service)n.append(node("small","Next service: "+a.next_service+(a.next_service<today()?" · Overdue":"")));}
 if(!a.retired){const b=node("button","Update / record event","goal-secondary");b.type="button";b.addEventListener("click",()=>openEvent(a));n.append(b);}
 else n.append(node("small","Retired / settled"));
 box.append(n);
 }
 if(!box.children.length)box.append(node("p","No matching records."));
}
function render(){
 const box=el("netWorthTotals");box.replaceChildren();
 for(const t of totals){const n=tile(t.currency+" net worth",money(t.net_worth,t.currency),"Assets "+money(t.total_assets,t.currency)+" · Liabilities "+money(t.total_liabilities,t.currency));
 for(const [k,label] of [["savings","Personal savings"],["account_cash","Own Amanah cash"],["receivables","Loan receivables"],["physical_assets","Physical assets"],["investments","Investments"],["external_cash","Other cash"],["loan_liabilities","Amanah debts"],["account_overdraft","Account overdrafts"],["external_liabilities","External debts"]])n.append(node("small",label+": "+money(t[k],t.currency)));
 box.append(n);}
 renderCards();
 const h=el("assetHistory");h.replaceChildren();for(const e of events){const a=assets.find(x=>x.id===e.asset_id);h.append(tile(e.event_date+" · "+(a?.name||"Asset"),e.kind+" · "+money(e.amount,a?.currency||"MVR"),(e.note||"")+(e.next_service?" · Next service "+e.next_service:"")));}if(!events.length)h.append(node("p","No asset events yet."));
 const sh=el("netSnapshotHistory");sh.replaceChildren();for(const s of snapshots){const n=tile(new Date(s.captured_at).toLocaleString("en-GB",{timeZone:"Indian/Maldives"}),"Saved snapshot",s.note);for(const t of s.totals)n.append(node("small",t.currency+" net worth: "+money(t.net_worth,t.currency)+" · Assets "+money(t.total_assets,t.currency)+" · Debts "+money(t.total_liabilities,t.currency)));sh.append(n);}if(!snapshots.length)sh.append(node("p","No snapshots yet."));
 el("assetContent").hidden=false;
}
async function refresh(u){
 const token=++epoch;if(!cfg||!u)return false;
 try{const r=await Promise.all([cfg.client.rpc("dhaftar_asset_register_v5"),cfg.client.rpc("dhaftar_net_worth_v5"),cfg.client.from("dhaftar_asset_events_v5").select("*").eq("user_id",u).order("event_date",{ascending:false}).order("created_at",{ascending:false}).limit(50),cfg.client.from("dhaftar_net_worth_snapshots_v5").select("*").eq("user_id",u).order("captured_at",{ascending:false}).limit(50)]);
 if(token!==epoch||cfg.user()!==u)return false;for(const x of r)if(x.error)throw x.error;if(!r.every(x=>Array.isArray(x.data)))throw Error("Invalid server response");
 [assets,totals,events,snapshots]=r.map(x=>x.data);ready=true;render();status("assetStatus","Latest balances · showing up to 50 recent events and snapshots.");return true;
 }catch(e){if(token===epoch&&cfg.user()===u){ready=false;el("assetContent").hidden=true;status("assetStatus",e.message||"Personal asset records unavailable.",true);}return false;}
}
function eventFields(){const k=el("assetEventKind").value;el("assetServiceLabel").hidden=k!=="maintenance";el("assetEventAmountLabel").hidden=k==="retirement";el("assetEventAmount").required=k!=="retirement";el("assetEventNote").required=k==="retirement";if(k!=="maintenance")el("assetNextService").value="";if(k==="retirement")el("assetEventAmount").value="0";}
function openEvent(a){if(busy||!ready)return;selected=a;el("assetEventTitle").textContent="Update "+a.name;el("assetEventKind").value="valuation";el("assetEventKind").querySelector('option[value="maintenance"]').disabled=a.kind!=="physical";el("assetEventDate").value=today();el("assetEventDate").min=a.acquired_on;el("assetEventDate").max=today();el("assetEventAmount").value=Number(a.current_value).toFixed(2);el("assetEventNote").value="";eventFields();el("assetEventForm").hidden=false;el("assetEventForm").scrollIntoView({block:"nearest"});}
async function write(form,scope,rpc,payload,statusId,done){
 const u=cfg.user();if(!ready||busy||!u)return;busy=true;const b=form.querySelector('button[type="submit"]');b.disabled=true;let request=null,prior=true,saved=false;
 try{prior=root.DhaftarRequests.hasPending(u,scope);request=await root.DhaftarRequests.begin(u,scope,payload);const r=await cfg.client.rpc(rpc,{p_id:request.id,...payload});if(r.error)throw r.error;saved=true;if(cfg.user()===u)done();root.DhaftarRequests.finish(request);if(cfg.user()===u){const ok=await refresh(u);status(statusId,ok?"Saved successfully.":"Saved. Refresh to view latest values.",!ok);}}
 catch(e){if(!saved&&request&&!prior&&root.DhaftarRequests.definiteRejection(e)){try{root.DhaftarRequests.finish(request);}catch(_){}}if(cfg.user()===u)status(statusId,saved?"Saved; refresh before another entry.":(e.message||"Unable to confirm.")+" Retry identical details if uncertain.",true);}
 finally{busy=false;b.disabled=false;}
}
function bind(options){
 cfg=options;el("assetDate").value=today();el("assetDate").max=today();el("assetFilter").addEventListener("change",renderCards);el("assetEventKind").addEventListener("change",eventFields);el("assetEventCancel").addEventListener("click",()=>{if(!busy){selected=null;el("assetEventForm").hidden=true;}});
 el("assetCreateForm").addEventListener("submit",e=>{e.preventDefault();const p={p_name:el("assetName").value.trim(),p_kind:el("assetKind").value,p_currency:el("assetCurrency").value,p_date:el("assetDate").value,p_cost:amount(el("assetCost").value),p_value:amount(el("assetValue").value),p_note:el("assetNote").value.trim()||null};if(!p.p_name||!p.p_date||p.p_date>today()||p.p_cost===null||p.p_value===null){status("assetCreateStatus","Enter valid details and amounts.",true);return;}if(!root.confirm("Confirm this is yours and not already included in Amanah balances?"))return;void write(e.currentTarget,"personal-asset","dhaftar_create_asset_v5",p,"assetCreateStatus",()=>{el("assetCreateForm").reset();el("assetDate").value=today();});});
 el("assetEventForm").addEventListener("submit",e=>{e.preventDefault();if(!selected)return;const kind=el("assetEventKind").value,p={p_asset:selected.id,p_kind:kind,p_date:el("assetEventDate").value,p_amount:kind==="retirement"?0:amount(el("assetEventAmount").value),p_next:kind==="maintenance"?el("assetNextService").value||null:null,p_note:el("assetEventNote").value.trim()||null};if(!p.p_date||p.p_date>today()||p.p_amount===null||kind==="retirement"&&(!p.p_note||p.p_note.length<3)){status("assetEventStatus","Check event details; retirement needs a reason.",true);return;}if(kind==="retirement"&&!root.confirm("Retire or settle this record? History is retained; it will no longer count toward net worth."))return;void write(e.currentTarget,"asset-event","dhaftar_record_asset_event_v5",p,"assetEventStatus",()=>{selected=null;el("assetEventForm").hidden=true;});});
 el("netSnapshotForm").addEventListener("submit",e=>{e.preventDefault();void write(e.currentTarget,"net-worth-snapshot","dhaftar_save_net_worth_v5",{p_note:el("netSnapshotNote").value.trim()||null},"netSnapshotStatus",()=>{el("netSnapshotNote").value="";});});
}
root.PersonalAssets=Object.freeze({bind,refresh,clear,amount});
})(globalThis);
