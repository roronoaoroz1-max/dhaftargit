/* Private recurring payments; no automatic bank debits or accounting entries. */
(function(root){
 "use strict";
 const el=id=>document.getElementById(id);
 const node=(tag,t,cls)=>{const n=document.createElement(tag);if(t!==undefined)n.textContent=String(t);if(cls)n.className=cls;return n;};
 let cfg=null, rows=[], selected=null, epoch=0, busy=false, ready=false;
 const money=(a,c)=>c+" "+Number(a).toLocaleString("en",{minimumFractionDigits:2,maximumFractionDigits:2});
 function cents(s){if(!/^\d+(?:\.\d{1,2})?$/.test(String(s).trim()))return null;const n=Math.round(Number(s)*100);return Number.isSafeInteger(n)&&n>=0&&n<1e14?n:null;}
 function status(t,error=false){el("recurringPersonalStatus").textContent=t;el("recurringPersonalStatus").classList.toggle("is-error",error);}
 function daysBetween(a,b){return Math.round((Date.parse(b+"T00:00:00Z")-Date.parse(a+"T00:00:00Z"))/86400000);}
 function urgency(s,today){const d=daysBetween(today,s.next_due);return !s.active?"Paused":d<0?"Overdue by "+(-d)+" day(s)":d===0?"Due today":d<=s.remind_days?"Due in "+d+" day(s)":"Upcoming";}
 function clear(){++epoch;rows=[];selected=null;ready=false;el("recurringPersonalCards").replaceChildren();el("recurringPersonalHistory").replaceChildren();el("recurringConfirmForm").hidden=true;el("recurringCreateForm").reset();status("Sign in to view schedules.");}
 function render(history){
  const cards=el("recurringPersonalCards");cards.replaceChildren();
  const today=cfg.today();
  for(const s of [...rows].sort((a,b)=>Number(b.active)-Number(a.active)||a.next_due.localeCompare(b.next_due)||a.title.localeCompare(b.title))){
   const card=node("div",undefined,"field");card.style.padding="12px";card.style.border="1px solid var(--line)";card.style.borderRadius="12px";
   const label=node("strong",s.title),u=node("strong",urgency(s,today));
   if(s.active&&daysBetween(today,s.next_due)<=s.remind_days)u.style.color="var(--warning)";
   card.append(label,node("span",money(s.amount,s.currency)+" · Every "+s.interval_months+" month(s)"),node("span","Next due: "+s.next_due),u);
   if(s.active){const b=node("button","Record payment","history-button primary");b.type="button";b.disabled=busy;b.addEventListener("click",()=>openPayment(s));card.append(b);}
   const toggle=node("button",s.active?"Pause":"Resume","history-button");toggle.type="button";toggle.disabled=busy;toggle.addEventListener("click",()=>void setActive(s,!s.active));card.append(toggle);
   cards.append(card);
  }
  if(!rows.length)cards.append(node("p","No recurring payments yet."));
  const list=el("recurringPersonalHistory");list.replaceChildren();
  for(const p of history){
   const title=rows.find(r=>r.id===p.schedule_id)?.title||"Recurring payment";
   const item=node("p",title+" · "+money(p.amount,p.currency)+" · Due "+p.due_date+" · Paid "+p.paid_on+(p.note?" · "+p.note:""));list.append(item);
  }
  if(!history.length)list.append(node("p","No confirmed payments yet."));
 }
 async function refresh(){
  if(!cfg||!cfg.userId())return false;
  const token=++epoch,u=cfg.userId();
  try{
   const [s,h]=await Promise.all([cfg.client.from("dhaftar_recurring_schedules_v3").select("*").eq("user_id",u).order("next_due").limit(1000),cfg.client.from("dhaftar_recurring_payments_v3").select("*").eq("user_id",u).order("created_at",{ascending:false}).order("id",{ascending:false}).limit(50)]);
   if(token!==epoch||cfg.userId()!==u)return false;
   if(s.error||h.error)throw s.error||h.error;
   rows=s.data||[];ready=true;render(h.data||[]);status("Showing upcoming schedules and the latest 50 payments.");return true;
  }catch(e){if(token===epoch&&cfg.userId()===u){ready=false;rows=[];el("recurringPersonalCards").replaceChildren();el("recurringPersonalHistory").replaceChildren();status(e.message||"Unable to load recurring payments.",true);}return false;}
 }
 function openPayment(s){
  if(busy||!ready)return;
  selected={...s};el("recurringConfirmTitle").textContent="Confirm "+s.title+" · due "+s.next_due;
  el("recurringActual").value=Number(s.amount).toFixed(2);el("recurringPaidOn").value=cfg.today();el("recurringPaidOn").max=cfg.today();el("recurringNote").value="";
  el("recurringConfirmForm").hidden=false;el("recurringConfirmForm").scrollIntoView({block:"nearest"});el("recurringActual").focus();
 }
 async function write(form,scope,rpc,payload,onSuccess){
  const user=cfg.userId();if(busy||!user||!ready)return;
  busy=true;const button=form.querySelector("button[type=submit]");button.disabled=true;
  let request=null,prior=true,saved=false;
  try{
   prior=root.DhaftarRequests.hasPending(user,scope);
   request=await root.DhaftarRequests.begin(user,scope,payload);
   const r=await cfg.client.rpc(rpc,{p_id:request.id,...payload});if(r.error)throw r.error;
   saved=true;
   if(cfg.userId()===user)onSuccess();
   root.DhaftarRequests.finish(request);
   if(cfg.userId()===user){const ok=await refresh();status(ok?"Saved successfully.":"Saved; refresh to view latest records.",!ok);}
  }catch(e){
   if(!saved&&request&&!prior&&root.DhaftarRequests.definiteRejection(e)){try{root.DhaftarRequests.finish(request);}catch(_){}}
   if(cfg.userId()===user)status(saved?"Saved; refresh before recording another payment.":(e.message||"Unable to confirm.")+" Retry with the same details if uncertain.",true);
  }finally{busy=false;button.disabled=false;}
 }
 async function setActive(s,active){
  if(busy||!ready||!cfg.userId())return;
  if(!root.confirm(active?"Resume this schedule? Its existing due date will be retained.":"Pause this schedule? History will be retained."))return;
  busy=true;const user=cfg.userId();
  try{const r=await cfg.client.from("dhaftar_recurring_schedules_v3").update({active}).eq("id",s.id).eq("user_id",user).select("id").single();if(r.error)throw r.error;if(cfg.userId()===user){await refresh();status(active?"Schedule resumed.":"Schedule paused.");}}
  catch(e){if(cfg.userId()===user)status(e.message||"Unable to update schedule.",true);}
  finally{busy=false;}
 }
 function bind(options){
  cfg=options;
  el("recurringDue").value=cfg.today();
  el("recurringReload").addEventListener("click",()=>void refresh());
  el("recurringCancel").addEventListener("click",()=>{if(!busy){selected=null;el("recurringConfirmForm").hidden=true;}});
  el("recurringCreateForm").addEventListener("submit",e=>{
   e.preventDefault();
   const title=el("recurringTitle").value.trim(),amount=cents(el("recurringAmount").value),currency=el("recurringCurrency").value,months=Number(el("recurringInterval").value),due=el("recurringDue").value,remind=Number(el("recurringReminder").value);
   if(!title||amount===null||!due||!["MVR","USD"].includes(currency)||![1,2,3,6,12].includes(months)||!Number.isInteger(remind)||remind<0||remind>30){status("Enter valid schedule details.",true);return;}
   void write(e.currentTarget,"recurring-schedule","dhaftar_create_schedule_v3",{p_title:title,p_amount:amount/100,p_currency:currency,p_months:months,p_due:due,p_remind:remind},()=>{el("recurringCreateForm").reset();el("recurringDue").value=cfg.today();});
  });
  el("recurringConfirmForm").addEventListener("submit",e=>{
   e.preventDefault();if(!selected)return;
   const s=selected,amount=cents(el("recurringActual").value),paid=el("recurringPaidOn").value,note=el("recurringNote").value.trim()||null;
   if(amount===null||!paid||paid>cfg.today()){status("Enter actual amount and a valid payment date.",true);return;}
   if(!root.confirm("Confirm actual payment of "+money(amount/100,s.currency)+" for "+s.title+" (due "+s.next_due+")?"))return;
   void write(e.currentTarget,"recurring-payment","dhaftar_confirm_recurring_v3",{p_schedule:s.id,p_due:s.next_due,p_paid:paid,p_amount:amount/100,p_note:note},()=>{selected=null;el("recurringConfirmForm").hidden=true;});
  });
 }
 root.RecurringPayments=Object.freeze({bind,refresh,clear});
})(globalThis);
