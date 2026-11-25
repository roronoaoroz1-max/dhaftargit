-- Synthetic database only. Schema copied from read-only catalog metadata; no production data.
create role anon nologin;
create role authenticated nologin;
create schema auth;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
create function public.is_admin() returns boolean language sql stable as $$ select auth.uid()='10000000-0000-4000-8000-000000000001'::uuid $$;
grant usage on schema auth,public to authenticated,anon;
grant execute on function auth.uid(),public.is_admin() to authenticated,anon;
insert into auth.users values ('10000000-0000-4000-8000-000000000001'),('10000000-0000-4000-8000-000000000002');
create table public.people (
id uuid default gen_random_uuid() not null,
user_id uuid default auth.uid() not null,
name text not null,
relationship text,
notes text,
created_at timestamp with time zone default now() not null,
PRIMARY KEY (id),
FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
UNIQUE (user_id, name)
);
alter table public.people enable row level security;
create table public.accounts (
id uuid default gen_random_uuid() not null,
user_id uuid default auth.uid() not null,
account_name text not null,
owner_id uuid not null,
holder_id uuid,
account_type text not null,
currency text not null,
opening_balance numeric(18,2) default 0 not null,
notes text,
created_at timestamp with time zone default now() not null,
CHECK ((account_type = ANY (ARRAY['custody'::text, 'savings'::text, 'cash'::text, 'other'::text]))),
CHECK ((currency = ANY (ARRAY['MVR'::text, 'USD'::text]))),
FOREIGN KEY (holder_id) REFERENCES people(id) ON DELETE SET NULL,
FOREIGN KEY (owner_id) REFERENCES people(id) ON DELETE RESTRICT,
PRIMARY KEY (id),
FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
alter table public.accounts enable row level security;
create table public.loans (
id uuid default gen_random_uuid() not null,
user_id uuid default auth.uid() not null,
source_account_id uuid,
lender_id uuid not null,
borrower_id uuid not null,
principal_amount numeric(18,2) not null,
currency text not null,
loan_date date,
date_is_estimated boolean default false not null,
installment_amount numeric(18,2),
installment_frequency text,
next_payment_date date,
status text default 'active'::text not null,
notes text,
created_at timestamp with time zone default now() not null,
FOREIGN KEY (borrower_id) REFERENCES people(id) ON DELETE RESTRICT,
CHECK ((currency = ANY (ARRAY['MVR'::text, 'USD'::text]))),
CHECK (((installment_amount IS NULL) OR (installment_amount > (0)::numeric))),
CHECK (((installment_frequency IS NULL) OR (installment_frequency = ANY (ARRAY['weekly'::text, 'monthly'::text, 'custom'::text])))),
FOREIGN KEY (lender_id) REFERENCES people(id) ON DELETE RESTRICT,
PRIMARY KEY (id),
CHECK ((principal_amount > (0)::numeric)),
FOREIGN KEY (source_account_id) REFERENCES accounts(id) ON DELETE SET NULL,
CHECK ((status = ANY (ARRAY['active'::text, 'paid'::text, 'overdue'::text, 'cancelled'::text]))),
FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
alter table public.loans enable row level security;
create table public.loan_payments (
id uuid default gen_random_uuid() not null,
user_id uuid default auth.uid() not null,
loan_id uuid not null,
payment_date date not null,
amount numeric(18,2) not null,
payment_method text,
notes text,
created_at timestamp with time zone default now() not null,
CHECK ((amount > (0)::numeric)),
FOREIGN KEY (loan_id) REFERENCES loans(id) ON DELETE CASCADE,
PRIMARY KEY (id),
FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
alter table public.loan_payments enable row level security;
create table public.account_transactions (
id uuid default gen_random_uuid() not null,
user_id uuid default auth.uid() not null,
account_id uuid not null,
transaction_date date not null,
transaction_type text not null,
amount numeric(18,2) not null,
description text,
reference_number text,
created_at timestamp with time zone default now() not null,
FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE,
CHECK ((amount > (0)::numeric)),
PRIMARY KEY (id),
CHECK ((transaction_type = ANY (ARRAY['deposit'::text, 'withdrawal'::text, 'adjustment_in'::text, 'adjustment_out'::text]))),
FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
alter table public.account_transactions enable row level security;
create table public.stock_items (
id uuid default gen_random_uuid() not null,
name text not null,
category text default 'Other'::text not null,
unit text not null,
archived boolean default false not null,
created_by uuid default auth.uid() not null,
created_at timestamp with time zone default now() not null,
updated_at timestamp with time zone default now() not null,
CHECK (((length(TRIM(BOTH FROM name)) >= 1) AND (length(TRIM(BOTH FROM name)) <= 80))),
PRIMARY KEY (id),
CHECK (((length(TRIM(BOTH FROM unit)) >= 1) AND (length(TRIM(BOTH FROM unit)) <= 20)))
);
alter table public.stock_items enable row level security;
create table public.stock_purchases (
id uuid default gen_random_uuid() not null,
stock_item_id uuid not null,
purchased_on date not null,
quantity numeric(14,3) not null,
amount numeric(14,2) default 0 not null,
note text,
run_out_on date,
ended_reason text,
ended_on date,
created_by uuid default auth.uid() not null,
created_at timestamp with time zone default now() not null,
updated_at timestamp with time zone default now() not null,
voided_at timestamp with time zone,
voided_by uuid,
void_reason text,
CHECK (((ended_on IS NULL) OR (ended_on >= purchased_on))),
CHECK (((run_out_on IS NULL) OR (run_out_on >= purchased_on))),
CHECK ((amount >= (0)::numeric)),
CHECK (((ended_reason IS NULL) OR (ended_reason = 'restocked'::text))),
CHECK (((note IS NULL) OR (length(note) <= 120))),
PRIMARY KEY (id),
CHECK ((quantity > (0)::numeric)),
FOREIGN KEY (stock_item_id) REFERENCES stock_items(id) ON DELETE CASCADE
);
alter table public.stock_purchases enable row level security;
create table public.dhaftar_bills (
id uuid default gen_random_uuid() not null,
bill_type text not null,
billing_month date not null,
amount numeric(14,2) default 0 not null,
notes text,
created_by uuid default auth.uid(),
updated_by uuid default auth.uid(),
created_at timestamp with time zone default now() not null,
updated_at timestamp with time zone default now() not null,
CHECK ((amount >= (0)::numeric)),
CHECK ((EXTRACT(day FROM billing_month) = (1)::numeric)),
FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
PRIMARY KEY (id),
UNIQUE (bill_type, billing_month),
FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL
);
alter table public.dhaftar_bills enable row level security;
create table public.dhaftar_payments (
id uuid default gen_random_uuid() not null,
person_id uuid,
payer_name text not null,
payment_date date default CURRENT_DATE not null,
billing_month date not null,
amount numeric(14,2) not null,
note text,
created_by uuid default auth.uid(),
created_at timestamp with time zone default now() not null,
CHECK ((amount > (0)::numeric)),
CHECK ((EXTRACT(day FROM billing_month) = (1)::numeric)),
FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
FOREIGN KEY (person_id) REFERENCES people(id) ON DELETE SET NULL,
PRIMARY KEY (id)
);
alter table public.dhaftar_payments enable row level security;
create table public.dhaftar_spending_entries (
id uuid default gen_random_uuid() not null,
spending_type text not null,
category text not null,
expense_date date default CURRENT_DATE not null,
amount numeric(14,2) not null,
person_name text,
provider_name text,
activity_group text,
notes text,
created_by uuid default auth.uid() not null,
created_at timestamp with time zone default now() not null,
updated_at timestamp with time zone default now() not null,
CHECK (((activity_group IS NULL) OR (length(activity_group) <= 120))),
CHECK ((amount > (0)::numeric)),
CHECK (((length(TRIM(BOTH FROM category)) >= 1) AND (length(TRIM(BOTH FROM category)) <= 60))),
FOREIGN KEY (created_by) REFERENCES auth.users(id),
CHECK (((notes IS NULL) OR (length(notes) <= 500))),
CHECK (((person_name IS NULL) OR (length(person_name) <= 80))),
PRIMARY KEY (id),
CHECK (((provider_name IS NULL) OR (length(provider_name) <= 120))),
CHECK ((spending_type = ANY (ARRAY['enjoyment'::text, 'medical'::text])))
);
alter table public.dhaftar_spending_entries enable row level security;
create table public.amanah_personal_savings_transactions (
id uuid default gen_random_uuid() not null,
user_id uuid default auth.uid() not null,
transaction_date date default CURRENT_DATE not null,
transaction_type text not null,
amount numeric(14,2) not null,
note text,
created_at timestamp with time zone default now() not null,
CHECK ((amount > (0)::numeric)),
PRIMARY KEY (id),
CHECK ((transaction_type = ANY (ARRAY['deposit'::text, 'withdrawal'::text]))),
FOREIGN KEY (user_id) REFERENCES auth.users(id)
);
alter table public.amanah_personal_savings_transactions enable row level security;
create view public.loan_balances with (security_invoker=true) as  WITH payment_totals AS (
         SELECT loan_payments.loan_id,
            sum(loan_payments.amount) AS total_repaid,
            max(loan_payments.payment_date) AS last_payment_date
           FROM loan_payments
          GROUP BY loan_payments.loan_id
        )
 SELECT loans.id AS loan_id,
    loans.user_id,
    loans.source_account_id,
    loans.lender_id,
    lender.name AS lender_name,
    lender.relationship AS lender_relationship,
    loans.borrower_id,
    borrower.name AS borrower_name,
    borrower.relationship AS borrower_relationship,
    loans.principal_amount,
    loans.currency,
    loans.loan_date,
    loans.date_is_estimated,
    loans.installment_amount,
    loans.installment_frequency,
    loans.next_payment_date,
    COALESCE(payments.total_repaid, 0::numeric) AS total_repaid,
    GREATEST(loans.principal_amount - COALESCE(payments.total_repaid, 0::numeric), 0::numeric) AS remaining_amount,
    payments.last_payment_date,
        CASE
            WHEN loans.status = 'cancelled'::text THEN 'cancelled'::text
            WHEN (loans.principal_amount - COALESCE(payments.total_repaid, 0::numeric)) <= 0::numeric THEN 'paid'::text
            WHEN loans.next_payment_date IS NOT NULL AND loans.next_payment_date < CURRENT_DATE THEN 'overdue'::text
            ELSE 'active'::text
        END AS calculated_status,
    loans.notes,
    loans.created_at
   FROM loans loans
     JOIN people lender ON lender.id = loans.lender_id
     JOIN people borrower ON borrower.id = loans.borrower_id
     LEFT JOIN payment_totals payments ON payments.loan_id = loans.id;;
grant select,insert,update,delete on all tables in schema public to authenticated;
grant select on public.loan_balances to authenticated;
create policy fixture_admin on public.people for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy fixture_admin on public.accounts for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy fixture_admin on public.loans for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy fixture_admin on public.loan_payments for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy fixture_admin on public.account_transactions for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy fixture_admin on public.stock_items for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy fixture_admin on public.stock_purchases for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy fixture_admin on public.dhaftar_bills for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy fixture_admin on public.dhaftar_payments for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy fixture_admin on public.dhaftar_spending_entries for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy fixture_admin on public.amanah_personal_savings_transactions for all to authenticated using (public.is_admin() and user_id=auth.uid()) with check (public.is_admin() and user_id=auth.uid());
revoke update,delete on public.amanah_personal_savings_transactions from authenticated;
