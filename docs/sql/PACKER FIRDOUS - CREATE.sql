-- PACKER FIRDOUS - CREATE.sql
-- New packing staff FIRDOUS, Al Quoz (no login; picked on production / cleaning slips).
-- Undo with: PACKER FIRDOUS - REVERT.sql
insert into public.staff (name, role, active, branch_id, can_login)
select 'FIRDOUS', 'PACKER', true, (select id from public.branches where code = 'MGAZ'), false
where not exists (select 1 from public.staff where upper(name) = 'FIRDOUS');
select id, name, role, active from public.staff where name = 'FIRDOUS';
