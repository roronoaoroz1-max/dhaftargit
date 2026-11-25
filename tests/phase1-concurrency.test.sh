#!/usr/bin/env bash
# Disposable CI database only. Never point this script at a live database.
set -euo pipefail
[[ "${PGHOST:-}" == 127.0.0.1 && "${PGDATABASE:-}" == dhaftar_test && "${PGUSER:-}" == fixture ]] || { echo "Refusing non-fixture database"; exit 1; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
auth="set role authenticated; select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',false);"
psqlq(){ psql -X -v ON_ERROR_STOP=1 -qAt -c "$auth $1"; }
run_pair(){
  local left="$1" right="$2" expected="$3" a=0 b=0
  psqlq "begin; $left; select pg_sleep(0.4); commit;" >"$tmp/left" 2>&1 & local pid1=$!
  psqlq "begin; $right; select pg_sleep(0.4); commit;" >"$tmp/right" 2>&1 & local pid2=$!
  wait "$pid1" || a=$?
  wait "$pid2" || b=$?
  if [[ "$expected" == both ]]; then
    if ((a!=0 || b!=0)); then cat "$tmp/left" "$tmp/right"; return 1; fi
  else
    if ! { ((a==0 && b!=0)) || ((b==0 && a!=0)); }; then cat "$tmp/left" "$tmp/right"; return 1; fi
    grep -Eq 'Withdrawal exceeds (available|unallocated) savings|Repayment exceeds latest combined outstanding balance|Repayment exceeds outstanding loan balance' "$tmp/left" "$tmp/right"
  fi
}
assert_sql(){ local result; result=$(psqlq "$1" | tail -n 1); [[ "$result" == t ]] || { echo "Assertion failed: $1"; return 1; }; }
# Two concurrent retries for one request: exactly one deposit.
deposit="select public.dhaftar_record_savings_v1('20000000-0000-4000-8000-000000000001','2026-01-01','deposit',100,null)"
run_pair "$deposit" "$deposit" both
assert_sql "select count(*)=1 and sum(amount)=100 from public.amanah_personal_savings_transactions"
# Competing withdrawals cannot collectively exceed available savings.
run_pair "select public.dhaftar_record_savings_v1('20000000-0000-4000-8000-000000000002','2026-01-02','withdrawal',80,null)" "select public.dhaftar_record_savings_v1('20000000-0000-4000-8000-000000000003','2026-01-02','withdrawal',80,null)" one
assert_sql "select public.dhaftar_savings_balance_v1()=20"
# Concurrent household retries should create exactly one receipt/payment.
h="select public.dhaftar_record_household_payment_v1('20000000-0000-4000-8000-000000000004','Fixture payer','2026-01-01','2026-01-01',35,null)"
run_pair "$h" "$h" both
assert_sql "select count(*)=1 from public.dhaftar_payments"
# Same stock request must not create two cycles.
psqlq "insert into public.stock_items(id,name,unit) values('20000000-0000-4000-8000-000000000005','Fixture stock','pcs')" >/dev/null
s="select public.dhaftar_record_stock_purchase_v1('20000000-0000-4000-8000-000000000006','20000000-0000-4000-8000-000000000005','2026-01-01',2,50,null)"
run_pair "$s" "$s" both
assert_sql "select count(*)=1 from public.stock_purchases"
# Concurrent group repayments compete for one outstanding amount.
psqlq "insert into public.people(id,name) values('20000000-0000-4000-8000-000000000007','Fixture lender'),('20000000-0000-4000-8000-000000000008','Fixture borrower'); insert into public.loans(id,lender_id,borrower_id,principal_amount,currency,loan_date) values('20000000-0000-4000-8000-000000000009','20000000-0000-4000-8000-000000000007','20000000-0000-4000-8000-000000000008',100,'MVR','2026-01-01')" >/dev/null
run_pair "select public.dhaftar_record_group_repayment_v1('20000000-0000-4000-8000-000000000010','20000000-0000-4000-8000-000000000007','20000000-0000-4000-8000-000000000008','MVR','2026-01-02',80,null,null)" "select public.dhaftar_record_group_repayment_v1('20000000-0000-4000-8000-000000000011','20000000-0000-4000-8000-000000000007','20000000-0000-4000-8000-000000000008','MVR','2026-01-02',80,null,null)" one
assert_sql "select count(*)=1 and sum(amount)=80 from public.loan_payments"
echo "PASS: concurrent savings retries, competing withdrawals, household retries, stock retries and competing repayments"
