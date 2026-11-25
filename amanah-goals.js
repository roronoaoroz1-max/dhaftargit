/* Amanah phase 2: private savings goals and reconciliation. No Dad balance writes. */
(function(root){
 "use strict";
 const el=id=>document.getElementById(id);
 let cfg=null, data=null, generation=0, busy=new Set();
 const make=(tag,text,cls)=>{const node=document.createElement(tag);if(text!==undefined)node.textContent=String(text);if(cls)node.className=cls;return node;};
 const money=v=>cfg.formatMoney(Number(v));
 function cents(raw,allowZero=false){
  if(!/^(?:\d+)(?:\.\d{1,2})?$/.test(String(raw).trim()))return null;
  const c=Math.round(Number(raw)*100);
  return Number.isSafeInteger(c)&&c<100000000000000&&(allowZero?c>=0:c>0)?c:null;
 }
 function status(id,message,error=false){const n=el(id);n.textContent=message;n.className=error?"goal-error":"goal-status";}
 function tile(label,value,detail){
  const n=make("div",undefined,"goal-tile");n.append(make("small",label),make("strong",value));
  if(detail)n.append(make("small",detail));return n;
 }
 function dateTime(value){
  const d=new Date(value);return Number.isFinite(d.getTime())?d.toLocaleString("en-GB",{timeZone:"Indian/Maldives",dateStyle:"medium",timeStyle:"short"}):"—";
 }
 function hint(){
  const g=data?.goals.find(x=>x.id===el("allocationGoal").value);
  if(!g){el("allocationHint").textContent="Create and select a goal first.";return;}
  const release=el("allocationDirection").value==="release";
  const max=release?Number(g.allocated):Math.max(0,Math.min(Number(data.unallocated),Number(g.target_amount)-Number(g.allocated)));
  el("allocationHint").textContent=(release?"Available to release: ":"Available to allocate: ")+money(max)+".";
 }
 function render(){
  if(!data)return;
  el("goalSummary").replaceChildren(tile("My total savings",money(data.balance)),tile("Allocated to goals",money(data.allocated)),tile("Unallocated savings",money(data.unallocated),"Available for withdrawal or another goal"));
  const cards=el("goalCards"),select=el("allocationGoal"),previous=select.value;cards.replaceChildren();select.replaceChildren(make("option","Choose a goal"));select.firstChild.value="";
  for(const g of data.goals){
   const allocated=Number(g.allocated),target=Number(g.target_amount),percent=Math.max(0,Math.min(100,allocated/target*100));
   const card=tile(g.name,money(allocated)+" / "+money(target),g.target_date?"Target: "+g.target_date:"No target date");
   const track=make("div",undefined,"goal-progress"),fill=make("span");fill.style.width=percent+"%";track.append(fill);
   track.setAttribute("role","progressbar");track.setAttribute("aria-label",g.name+" progress");track.setAttribute("aria-valuemin","0");track.setAttribute("aria-valuemax","100");track.setAttribute("aria-valuenow",String(Math.round(percent)));
   card.append(track,make("small",percent>=100?"Target reached":Math.round(percent)+"% · "+money(Math.max(0,target-allocated))+" remaining"));cards.append(card);
   const opt=make("option",g.name+" · "+money(allocated));opt.value=g.id;select.append(opt);
  }
  if(!data.goals.length)cards.append(make("p","No goals yet. Create your first savings goal."));
  if([...select.options].some(x=>x.value===previous))select.value=previous;
  hint();
  const allocation=el("goalAllocationHistory");allocation.replaceChildren();
  for(const a of data.allocation_history){const n=make("div",undefined,"savings-history-row");const l=make("div");l.append(make("strong",a.name),make("small",dateTime(a.created_at)+(a.note?" · "+a.note:"")));n.append(l,make("strong",(Number(a.amount)>0?"+":"−")+money(Math.abs(Number(a.amount)))));allocation.append(n);}
  if(!data.allocation_history.length)allocation.append(make("p","No allocations yet."));
  let deposits=0,withdrawals=0;const tbody=el("goalMonthlyRows");tbody.replaceChildren();
  for(const m of data.monthly){const d=Number(m.deposits),w=Number(m.withdrawals);deposits+=d;withdrawals+=w;const row=make("tr");for(const value of [m.month.slice(0,7),money(d),money(w),money(d-w)])row.append(make("td",value));tbody.append(row);}
  el("goalMonthlySummary").replaceChildren(tile("12-month deposits",money(deposits)),tile("12-month withdrawals",money(withdrawals)),tile("12-month net",money(deposits-withdrawals)));
  const checks=el("bankCheckHistory");checks.replaceChildren();
  for(const r of data.checks){const n=tile(dateTime(r.created_at),Number(r.difference)===0?"Matched":"Difference: "+money(r.difference),r.note||"");n.append(make("small","Actual: "+money(r.actual)),make("small","Expected: "+money(r.expected)),make("small","Dad's cash: "+money(r.dad_cash)+" · My savings: "+money(r.personal_savings)));checks.append(n);}
  if(!data.checks.length)checks.append(make("p","No saved bank checks yet."));
  el("goalDashboardContent").hidden=false;
 }
 function validate(d){
  if(!d||!["balance","allocated","unallocated"].every(k=>Number.isFinite(Number(d[k]))&&d[k]!==null)||!["goals","monthly","allocation_history","checks"].every(k=>Array.isArray(d[k])))throw Error("Invalid savings dashboard response.");
 }
 async function refresh(userId){
  const version=++generation;
  if(!cfg||!userId)return false;
  try{
   const r=await cfg.client.rpc("dhaftar_savings_dashboard_v2");
   if(version!==generation||cfg.getUserId()!==userId)return false;
   if(r.error)throw r.error;
   validate(r.data);data=r.data;render();status("goalDashboardStatus","");return true;
  }catch(e){
   if(version!==generation||cfg.getUserId()!==userId)return false;
   data=null;el("goalDashboardContent").hidden=true;el("bankCheckHistory").replaceChildren(make("p","Bank history unavailable."));status("goalDashboardStatus","Savings goals unavailable. Reload to retry.",true);return false;
  }
 }
 async function write(form,scope,rpc,payload,statusId,reset){
  const userId=cfg.getUserId();
  if(!userId||busy.has(scope))return;
  busy.add(scope);const button=form.querySelector("button[type=submit]");button.disabled=true;
  let request=null,saved=false,prior=true;
  try{
   if(!data)throw Error("Refresh Amanah before saving.");
   prior=root.DhaftarRequests.hasPending(userId,scope);
   request=await root.DhaftarRequests.begin(userId,scope,payload);
   const r=await cfg.client.rpc(rpc,{p_id:request.id,...payload});
   if(r.error)throw r.error;
   saved=true;root.DhaftarRequests.finish(request);
   if(cfg.getUserId()!==userId)return;
   reset();status(statusId,"Saved. Refreshing…");await cfg.refreshAll();
   status(statusId,data?"Saved successfully.":"Saved. Reload to refresh the dashboard.",!data);
  }catch(e){
   if(!saved&&request&&!prior&&root.DhaftarRequests.definiteRejection(e)){try{root.DhaftarRequests.finish(request);}catch(_){}}
   if(cfg.getUserId()===userId)status(statusId,saved?"Saved. Reload to refresh before another entry.":(e.message||"Unable to confirm.")+" If uncertain, retry with the same details.",true);
  }finally{busy.delete(scope);button.disabled=false;}
 }
 function bind(options){
  cfg=options;
  el("allocationGoal").addEventListener("change",hint);el("allocationDirection").addEventListener("change",hint);
  el("createGoalForm").addEventListener("submit",e=>{
   e.preventDefault();const name=el("goalName").value.trim(),target=cents(el("goalTarget").value),date=el("goalDate").value||null;
   if(!name||name.length>100||target===null){status("createGoalStatus","Enter a name and valid target amount.",true);return;}
   void write(e.currentTarget,"savings-goal","dhaftar_create_goal_v2",{p_name:name,p_target:target/100,p_date:date},"createGoalStatus",()=>el("createGoalForm").reset());
  });
  el("allocateGoalForm").addEventListener("submit",e=>{
   e.preventDefault();const goal=el("allocationGoal").value,amount=cents(el("allocationAmount").value),note=el("allocationNote").value.trim()||null;
   if(!goal||amount===null){status("allocationStatus","Choose a goal and enter a valid amount.",true);return;}
   const sign=el("allocationDirection").value==="release"?-1:1;
   void write(e.currentTarget,"goal-allocation","dhaftar_allocate_goal_v2",{p_goal:goal,p_amount:sign*amount/100,p_note:note},"allocationStatus",()=>{el("allocationAmount").value="";el("allocationNote").value="";});
  });
  el("bankCheckForm").addEventListener("submit",e=>{
   e.preventDefault();const actual=cents(el("actualSharedBankBalance").value,true),note=el("bankCheckNote").value.trim()||null;
   if(actual===null){status("bankCheckStatus","Enter a valid non-negative bank balance above.",true);return;}
   if(!root.confirm("Save this bank balance check? This records a snapshot only."))return;
   void write(e.currentTarget,"bank-check","dhaftar_save_bank_check_v2",{p_actual:actual/100,p_note:note},"bankCheckStatus",()=>{el("bankCheckNote").value="";el("actualSharedBankBalance").value="";el("actualSharedBankBalance").dispatchEvent(new Event("input"));});
  });
 }
 root.AmanahGoals=Object.freeze({bind,refresh});
})(globalThis);
