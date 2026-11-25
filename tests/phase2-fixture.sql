-- Production view definition from catalog; synthetic fixture data only.
create view public.account_balances with (security_invoker=true) as  WITH transaction_totals AS (
         SELECT account_transactions.account_id,
            COALESCE(sum(account_transactions.amount) FILTER (WHERE account_transactions.transaction_type = 'deposit'::text), 0::numeric) AS total_deposits,
            COALESCE(sum(account_transactions.amount) FILTER (WHERE account_transactions.transaction_type = 'withdrawal'::text), 0::numeric) AS total_withdrawals,
            COALESCE(sum(account_transactions.amount) FILTER (WHERE account_transactions.transaction_type = 'adjustment_in'::text), 0::numeric) AS total_adjustments_in,
            COALESCE(sum(account_transactions.amount) FILTER (WHERE account_transactions.transaction_type = 'adjustment_out'::text), 0::numeric) AS total_adjustments_out
           FROM account_transactions
          GROUP BY account_transactions.account_id
        ), outstanding_loans AS (
         SELECT loan_balances.source_account_id,
            sum(loan_balances.remaining_amount) AS outstanding_amount
           FROM loan_balances
          WHERE loan_balances.source_account_id IS NOT NULL AND loan_balances.calculated_status <> 'cancelled'::text
          GROUP BY loan_balances.source_account_id
        )
 SELECT account.id AS account_id,
    account.user_id,
    account.account_name,
    account.account_type,
    account.currency,
    account.owner_id,
    owner.name AS owner_name,
    account.holder_id,
    holder.name AS holder_name,
    account.opening_balance,
    COALESCE(transactions.total_deposits, 0::numeric) AS total_deposits,
    COALESCE(transactions.total_withdrawals, 0::numeric) AS total_withdrawals,
    COALESCE(transactions.total_adjustments_in, 0::numeric) AS total_adjustments_in,
    COALESCE(transactions.total_adjustments_out, 0::numeric) AS total_adjustments_out,
    account.opening_balance + COALESCE(transactions.total_deposits, 0::numeric) + COALESCE(transactions.total_adjustments_in, 0::numeric) - COALESCE(transactions.total_withdrawals, 0::numeric) - COALESCE(transactions.total_adjustments_out, 0::numeric) AS total_managed_balance,
    COALESCE(loans.outstanding_amount, 0::numeric) AS outstanding_loans,
    account.opening_balance + COALESCE(transactions.total_deposits, 0::numeric) + COALESCE(transactions.total_adjustments_in, 0::numeric) - COALESCE(transactions.total_withdrawals, 0::numeric) - COALESCE(transactions.total_adjustments_out, 0::numeric) - COALESCE(loans.outstanding_amount, 0::numeric) AS available_balance,
    account.notes,
    account.created_at
   FROM accounts account
     JOIN people owner ON owner.id = account.owner_id
     LEFT JOIN people holder ON holder.id = account.holder_id
     LEFT JOIN transaction_totals transactions ON transactions.account_id = account.id
     LEFT JOIN outstanding_loans loans ON loans.source_account_id = account.id;
grant select on public.account_balances to authenticated;
