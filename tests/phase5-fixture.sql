-- Existing production view definition, synthetic data only.
create view public.personal_money_position with (security_invoker=true) as  SELECT balances.user_id,
    balances.currency,
    sum(
        CASE
            WHEN lender.relationship = 'Self'::text AND balances.calculated_status <> 'cancelled'::text THEN balances.remaining_amount
            ELSE 0::numeric
        END) AS owed_to_me,
    sum(
        CASE
            WHEN borrower.relationship = 'Self'::text AND balances.calculated_status <> 'cancelled'::text THEN balances.remaining_amount
            ELSE 0::numeric
        END) AS i_owe,
    sum(
        CASE
            WHEN lender.relationship = 'Self'::text AND balances.calculated_status <> 'cancelled'::text THEN balances.remaining_amount
            ELSE 0::numeric
        END) - sum(
        CASE
            WHEN borrower.relationship = 'Self'::text AND balances.calculated_status <> 'cancelled'::text THEN balances.remaining_amount
            ELSE 0::numeric
        END) AS net_personal_position
   FROM loan_balances balances
     JOIN people lender ON lender.id = balances.lender_id
     JOIN people borrower ON borrower.id = balances.borrower_id
  GROUP BY balances.user_id, balances.currency;
grant select on public.personal_money_position to authenticated;
