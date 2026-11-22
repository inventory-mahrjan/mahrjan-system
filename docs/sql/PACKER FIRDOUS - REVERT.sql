-- PACKER FIRDOUS - REVERT.sql (only if he was never used on a slip)
delete from public.staff where name = 'FIRDOUS' and role = 'PACKER' and auth_user_id is null;
